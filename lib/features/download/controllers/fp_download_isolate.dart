import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:metatagger/metatagger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:floaty/features/download/models/fp_download.dart';
import 'package:floaty/features/download/controllers/download_log.dart';
import 'package:floaty/features/download/controllers/fp_download_url_helper.dart';
// import 'package:floaty/features/api/models/definitions.dart';
// import 'package:floaty/features/api/repositories/fpapi_requests.dart';

/// Messages from main isolate to coordinator
class FPCoordinatorMessage {
  final String type;
  final Map<String, dynamic>? data;

  FPCoordinatorMessage({required this.type, this.data});

  Map<String, dynamic> toJson() => {'type': type, 'data': data};
  factory FPCoordinatorMessage.fromJson(Map<String, dynamic> json) =>
      FPCoordinatorMessage(type: json['type'], data: json['data']);
}

/// Messages from coordinator/workers back to main
class FPIsolateResponse {
  final String type;
  final Map<String, dynamic>? data;

  FPIsolateResponse({required this.type, this.data});

  Map<String, dynamic> toJson() => {'type': type, 'data': data};
  factory FPIsolateResponse.fromJson(Map<String, dynamic> json) =>
      FPIsolateResponse(type: json['type'], data: json['data']);
}

/// Manager for FP download isolate coordinator
class FPDownloadIsolateManager {
  Isolate? _isolate;
  SendPort? _isolateSendPort;
  final ReceivePort _receivePort = ReceivePort();
  final Completer<void> _readyCompleter = Completer<void>();
  final StreamController<FPIsolateResponse> _responseController =
      StreamController.broadcast();

  bool get isReady => _readyCompleter.isCompleted;
  Stream<FPIsolateResponse> get responses => _responseController.stream;

  /// Start the coordinator isolate
  Future<void> start(
    String dbPath,
    Map<String, dynamic> settings,
  ) async {
    if (_isolate != null) return;

    _isolate = await Isolate.spawn(_coordinatorEntryPoint, {
      'sendPort': _receivePort.sendPort,
      'dbPath': dbPath,
      'rootIsolateToken': RootIsolateToken.instance!,
      'settings': settings,
    });

    _receivePort.listen((msg) {
      if (_isolateSendPort == null && msg is SendPort) {
        _isolateSendPort = msg;
        _readyCompleter.complete();
        return;
      }
      if (msg is Map<String, dynamic>) {
        final response = FPIsolateResponse.fromJson(msg);
        _responseController.add(response);
      }
    });

    await _readyCompleter.future;
  }

  /// Stop the isolate
  Future<void> stop() async {
    if (_isolate == null) return;
    sendMessage(FPCoordinatorMessage(type: 'shutdown'));
    await Future.delayed(const Duration(milliseconds: 100));
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _isolateSendPort = null;
    _receivePort.close();
    await _responseController.close();
  }

  /// Send a message to the coordinator
  void sendMessage(FPCoordinatorMessage message) {
    if (!isReady) return;
    _isolateSendPort?.send(message.toJson());
  }

  /// Coordinator entry point - manages queue and spawns workers
  static Future<void> _coordinatorEntryPoint(Map<String, dynamic> args) async {
    final mainSendPort = args['sendPort'] as SendPort;
    final dbPath = args['dbPath'] as String;
    final rootIsolateToken = args['rootIsolateToken'] as RootIsolateToken;
    final settings = args['settings'] as Map<String, dynamic>;

    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    // Initialize coordinator state
    final coordinator = _FPDownloadCoordinator(
      mainSendPort: mainSendPort,
      dbPath: dbPath,
      rootIsolateToken: rootIsolateToken,
      settings: settings,
    );

    await coordinator.init();

    await for (var msg in receivePort) {
      if (msg is Map<String, dynamic>) {
        final message = FPCoordinatorMessage.fromJson(msg);
        await coordinator.handleMessage(message);

        if (message.type == 'shutdown') {
          await coordinator.dispose();
          receivePort.close();
          return;
        }
      }
    }
  }
}

/// Internal coordinator class that runs in the isolate
class _FPDownloadCoordinator {
  final SendPort mainSendPort;
  final String dbPath;
  final RootIsolateToken rootIsolateToken;
  Map<String, dynamic> settings;

  Database? _db;
  DownloadLog? _logger;

  final List<FPDownloadTask> _queue = [];
  final Map<int, _FPWorkerHandle> _activeWorkers = {};
  bool _running = false;
  Timer? _progressTimer;
  Timer? _rateLimitTimer;

  // Rate limit backoff
  Duration _currentBackoff = const Duration(seconds: 30);
  static const Duration _maxBackoff = Duration(minutes: 5);
  static const Duration _minBackoff = Duration(seconds: 30);

  _FPDownloadCoordinator({
    required this.mainSendPort,
    required this.dbPath,
    required this.rootIsolateToken,
    required this.settings,
  });

  Future<void> init() async {
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    _logger = DownloadLog();
    await _logger!.open();

    _db = await openDatabase(dbPath);

    // Create FP downloads table if not exists
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS FPDownloads (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        postId TEXT NOT NULL,
        attachmentId TEXT NOT NULL,
        attachmentType TEXT NOT NULL,
        title TEXT NOT NULL,
        creatorName TEXT,
        channelName TEXT,
        thumbnailPath TEXT NOT NULL,
        qualityLabel TEXT NOT NULL,
        downloadUrl TEXT NOT NULL,
        filePath TEXT NOT NULL,
        finalFilePath TEXT,
        useExternalPath INTEGER DEFAULT 0,
        duration REAL NOT NULL,
        state INTEGER NOT NULL DEFAULT 0,
        whitelabel TEXT NOT NULL,
        blogPostJson TEXT,
        postTitle TEXT,
        postDescription TEXT,
        releaseDate TEXT,
        retryAfter TEXT,
        retryCount INTEGER DEFAULT 0,
        downloaded INTEGER DEFAULT 0,
        UNIQUE(attachmentId, qualityLabel)
      )
    ''');

    await _loadQueue();

    _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _sendProgressUpdate();
    });

    // Check rate limited downloads periodically
    _rateLimitTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkRateLimitedDownloads();
    });

    _logger!.log('[FP] Download coordinator initialized');
  }

  Future<void> dispose() async {
    _progressTimer?.cancel();
    _rateLimitTimer?.cancel();

    await _logger?.close();
    await _db?.close();

    for (var worker in _activeWorkers.values) {
      worker.isolate.kill(priority: Isolate.immediate);
      worker.receivePort.close();
    }
    _activeWorkers.clear();
  }

  Future<void> handleMessage(FPCoordinatorMessage message) async {
    _logger?.log('[FP Coordinator] handleMessage: ${message.type}');

    switch (message.type) {
      case 'start':
        _running = true;
        await _loadQueue();
        _sendDownloadsList();
        await _updateQueue();
        _sendStateUpdate();
        break;

      case 'stop':
        _running = false;
        for (var worker in _activeWorkers.values) {
          worker.isolate.kill(priority: Isolate.immediate);
          worker.receivePort.close();
          worker.download.state = FPDownloadState.none;
          await _db!.update(
            'FPDownloads',
            {
              'state': FPDownloadState.none.index,
              'downloaded': worker.download.received,
            },
            where: 'id = ?',
            whereArgs: [worker.download.id],
          );
        }
        _activeWorkers.clear();
        await _loadQueue();
        _sendStateUpdate();
        _sendDownloadsList();
        break;

      case 'addDownloads':
        await _addDownloads(message.data!['downloads'] as List);
        break;

      case 'removeDownload':
        await _removeDownload(message.data!['id'] as int);
        break;

      case 'retryDownloads':
        await _retryDownloads();
        break;

      case 'removeByState':
        await _removeByState(
          FPDownloadState.values[message.data!['state'] as int],
        );
        break;

      case 'getDownloads':
        _sendDownloadsList();
        break;

      case 'updateDownloadUrl':
        await _updateDownloadUrl(
          message.data!['id'] as int,
          message.data!['newUrl'] as String,
        );
        break;

      case 'updateSettings':
        settings = message.data!;
        break;
    }
  }

  Future<void> _updateDownloadUrl(int id, String newUrl) async {
    if (_db == null) return;

    // Kill existing worker if it's running (it has an expired URL anyway)
    final existingWorker = _activeWorkers[id];
    if (existingWorker != null) {
      _logger?.log('[FP] Killing existing worker for URL update: $id');
      existingWorker.isolate.kill(priority: Isolate.immediate);
      existingWorker.receivePort.close();
      _activeWorkers.remove(id);
    }

    // Update in database - preserve downloaded bytes for resume
    await _db!.update(
      'FPDownloads',
      {
        'downloadUrl': newUrl,
        'state': FPDownloadState.none.index, // Reset to queued
        // NOTE: NOT resetting 'downloaded' so resume works with partial file
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    // Update in queue
    final download = _queue.firstWhere(
      (d) => d.id == id,
      orElse: () => FPDownloadTask(
        id: -1,
        postId: '',
        attachmentId: '',
        attachmentType: 'video',
        title: '',
        thumbnailPath: '',
        qualityLabel: '',
        downloadUrl: '',
        filePath: '',
        duration: 0,
        state: FPDownloadState.none,
        whitelabel: '',
      ),
    );

    if (download.id != -1) {
      download.downloadUrl = newUrl;
      download.state = FPDownloadState.none;
      // Keep download.downloaded intact so worker can resume from partial file
      _logger?.log(
          '[FP] Updated download URL for: ${download.title} (downloaded: ${download.downloaded} bytes)');
    }

    // Trigger queue update to immediately start a fresh worker with the new URL
    if (_running) {
      await _updateQueue();
    }

    _sendStateUpdate();
    _sendDownloadsList();
  }

  Future<void> _loadQueue() async {
    if (_db == null) return;

    final results = await _db!.query('FPDownloads');
    _queue.clear();

    for (var row in results) {
      final task = FPDownloadTask.fromSQL(row);

      // Reset orphaned downloading state
      if (task.state == FPDownloadState.downloading) {
        task.state = FPDownloadState.none;
        await _db!.update(
          'FPDownloads',
          {'state': FPDownloadState.none.index},
          where: 'id = ?',
          whereArgs: [task.id],
        );
      }

      // Reset expired rate limits
      if (task.state == FPDownloadState.rateLimited && task.canRetry) {
        _logger?.log('[FP] Clearing expired rate limit for: ${task.title}');
        task.state = FPDownloadState.none;
        task.retryAfter = null;
        task.retryCount = 0;
        await _db!.update(
          'FPDownloads',
          {
            'state': FPDownloadState.none.index,
            'retryAfter': null,
            'retryCount': 0,
          },
          where: 'id = ?',
          whereArgs: [task.id],
        );
      }

      _queue.add(task);
    }

    _logger?.log('[FP] Loaded ${_queue.length} downloads from database');
  }

  Future<void> _addDownloads(List<dynamic> downloads) async {
    if (_db == null) return;

    int added = 0;
    for (var downloadData in downloads) {
      final attachmentId = downloadData['attachmentId'];
      final qualityLabel = downloadData['qualityLabel'];

      if (attachmentId == null) continue;

      // Check if exists
      final existing = await _db!.query(
        'FPDownloads',
        where: 'attachmentId = ? AND qualityLabel = ?',
        whereArgs: [attachmentId, qualityLabel],
      );

      if (existing.isEmpty) {
        await _db!.insert('FPDownloads', {
          'postId': downloadData['postId'],
          'attachmentId': attachmentId,
          'attachmentType': downloadData['attachmentType'],
          'title': downloadData['title'],
          'creatorName': downloadData['creatorName'],
          'channelName': downloadData['channelName'],
          'thumbnailPath': downloadData['thumbnailPath'],
          'qualityLabel': qualityLabel,
          'downloadUrl': downloadData['downloadUrl'],
          'filePath': downloadData['filePath'],
          'finalFilePath': downloadData['finalFilePath'],
          'useExternalPath': downloadData['useExternalPath'] == true ? 1 : 0,
          'duration': downloadData['duration'],
          'state': 0,
          'whitelabel': downloadData['whitelabel'],
          'blogPostJson': downloadData['blogPostJson'],
          'postTitle': downloadData['postTitle'],
          'postDescription': downloadData['postDescription'],
          'releaseDate': downloadData['releaseDate'],
          'retryCount': 0,
          'downloaded': 0,
        });
        added++;
      } else {
        // Allow re-download if done or error
        final state = existing[0]['state'] as int;
        if (state >= 3) {
          await _db!.update(
            'FPDownloads',
            {'state': 0, 'downloaded': 0, 'retryCount': 0},
            where: 'id = ?',
            whereArgs: [existing[0]['id']],
          );
          added++;
        }
      }
    }

    await _loadQueue();
    _sendResponse(
      FPIsolateResponse(type: 'downloadsAdded', data: {'count': added}),
    );
    _sendStateUpdate();
    _sendDownloadsList();

    if (_running) {
      await _updateQueue();
    }
  }

  Future<void> _removeDownload(int id) async {
    if (_db == null) return;

    // Cancel if actively downloading
    if (_activeWorkers.containsKey(id)) {
      _activeWorkers[id]!.isolate.kill(priority: Isolate.immediate);
      _activeWorkers[id]!.receivePort.close();
      _activeWorkers.remove(id);
    }

    _queue.removeWhere((d) => d.id == id);
    await _db!.delete('FPDownloads', where: 'id = ?', whereArgs: [id]);

    _sendStateUpdate();
    _sendDownloadsList();
  }

  Future<void> _retryDownloads() async {
    for (var download in _queue) {
      if (download.state == FPDownloadState.rateLimited ||
          download.state == FPDownloadState.error) {
        download.state = FPDownloadState.none;
        download.retryCount = 0;
        await _db!.update(
          'FPDownloads',
          {'state': download.state.index, 'retryCount': 0, 'retryAfter': null},
          where: 'id = ?',
          whereArgs: [download.id],
        );
      }
    }

    // Reset backoff on manual retry
    _currentBackoff = _minBackoff;

    await _loadQueue();
    _sendStateUpdate();
    _sendDownloadsList();

    if (_running) {
      await _updateQueue();
    }
  }

  Future<void> _removeByState(FPDownloadState state) async {
    if (_db == null) return;
    if (state == FPDownloadState.downloading || state == FPDownloadState.post) {
      return;
    }

    _queue.removeWhere((d) => d.state == state);
    await _db!.delete(
      'FPDownloads',
      where: 'state = ?',
      whereArgs: [state.index],
    );

    _sendStateUpdate();
    _sendDownloadsList();
  }

  void _checkRateLimitedDownloads() {
    if (!_running) return;

    bool hasRetryable = false;
    for (var download in _queue) {
      if (download.state == FPDownloadState.rateLimited && download.canRetry) {
        download.state = FPDownloadState.none;
        hasRetryable = true;
      }
    }

    if (hasRetryable) {
      _updateQueue();
    }
  }

  Future<void> _updateQueue() async {
    // Remove completed workers
    final completedIds = <int>[];
    for (var entry in _activeWorkers.entries.toList()) {
      final download = _queue.firstWhere(
        (d) => d.id == entry.key,
        orElse: () => FPDownloadTask(
          id: -1,
          postId: '',
          attachmentId: '',
          attachmentType: '',
          title: '',
          thumbnailPath: '',
          qualityLabel: '',
          downloadUrl: '',
          filePath: '',
          duration: 0,
          state: FPDownloadState.none,
          whitelabel: '',
        ),
      );

      if (download.state == FPDownloadState.done ||
          download.state == FPDownloadState.rateLimited ||
          download.state == FPDownloadState.expired ||
          download.state == FPDownloadState.error) {
        entry.value.isolate.kill(priority: Isolate.immediate);
        entry.value.receivePort.close();
        completedIds.add(entry.key);

        await _db!.update(
          'FPDownloads',
          download.toSQL(),
          where: 'id = ?',
          whereArgs: [download.id],
        );

        // If completed successfully, add to offline content
        if (download.state == FPDownloadState.done) {
          await _addToOfflineContent(download);
        }
      }
    }

    for (var id in completedIds) {
      _activeWorkers.remove(id);
    }

    // Start new downloads
    final maxThreads = settings['downloadThreads'] ?? 3;
    if (_running && _activeWorkers.length < maxThreads) {
      final availableSlots = maxThreads - _activeWorkers.length;

      for (var i = 0; i < availableSlots; i++) {
        final nextDownload = _queue.firstWhere(
          (d) =>
              d.state == FPDownloadState.none &&
              !_activeWorkers.containsKey(d.id),
          orElse: () => FPDownloadTask(
            id: -1,
            postId: '',
            attachmentId: '',
            attachmentType: '',
            title: '',
            thumbnailPath: '',
            qualityLabel: '',
            downloadUrl: '',
            filePath: '',
            duration: 0,
            state: FPDownloadState.none,
            whitelabel: '',
          ),
        );

        if (nextDownload.id == -1) break;

        await _startWorker(nextDownload);
      }
    }

    _sendStateUpdate();
    _sendDownloadsList();
  }

  Future<void> _addToOfflineContent(FPDownloadTask download) async {
    if (_db == null) return;

    _logger?.log('[FP] Adding to offline content: ${download.title}');
    _logger?.log('[FP] File path: ${download.filePath}');
    _logger?.log('[FP] Has blog post: ${download.blogPost != null}');

    try {
      // // Fetch blog post if missing
      // if (download.blogPost == null && download.postId.isNotEmpty) {
      //   _logger?.log('[FP] Blog post missing, fetching from API...');
      //   try {
      //     // final api = FPAPIRequests();
      //     // final result = await api.getBlogPost(
      //     //   id: download.postId,
      //     //   whitelabel: download.whitelabel,
      //     // );

      //     if (result != null) {
      //       download.blogPost = result;
      //       _logger?.log('[FP] Successfully fetched blog post from API');

      //       // Update database with blog post
      //       await _db!.update(
      //         'FPDownloads',
      //         {'blogPostJson': jsonEncode(result.toJson())},
      //         where: 'id = ?',
      //         whereArgs: [download.id],
      //       );
      //     } else {
      //       _logger?.warn('[FP] Failed to fetch blog post from API');
      //     }
      //   } catch (e) {
      //     _logger?.error('[FP] Error fetching blog post: $e');
      //   }
      // }

      // Write metadata to file if we have blog post data
      if (download.blogPost != null) {
        _logger?.log('[FP] Writing metadata tags...');
        final tagger = MetaTagger();
        final tags = <MetadataTag>[
          // Standard tags for media players
          MetadataTag.text(CommonTags.title, download.title),
          if (download.creatorName != null)
            MetadataTag.text(CommonTags.artist, download.creatorName!),
          if (download.channelName != null)
            MetadataTag.text(CommonTags.album, download.channelName!),
          if (download.blogPost?.text != null)
            MetadataTag.text(CommonTags.comment, download.blogPost!.text!),
          if (download.releaseDate != null)
            MetadataTag.text(
                CommonTags.date, download.releaseDate!.toIso8601String()),
        ];

        // Only add custom FP tags for INTERNAL offline library downloads
        // External downloads should not have these tags
        if (!download.useExternalPath) {
          _logger
              ?.log('[FP] Adding custom Floatplane tags for offline library');
          tags.addAll([
            MetadataTag.text(
                'FP_BLOGPOST_DATA', jsonEncode(download.blogPost!.toJson())),
            MetadataTag.text('FP_ATTACHMENT_ID', download.attachmentId),
            MetadataTag.text('FP_QUALITY', download.qualityLabel),
            MetadataTag.text('FP_WHITELABEL', download.whitelabel),
            MetadataTag.text(
                'FP_DOWNLOADED_AT', DateTime.now().toIso8601String()),
          ]);
        }

        // Add thumbnail as album art if available
        try {
          final thumbnailFile = File(download.thumbnailPath);
          if (await thumbnailFile.exists()) {
            final thumbnailBytes = await thumbnailFile.readAsBytes();
            _logger
                ?.log('[FP] Adding cover art (${thumbnailBytes.length} bytes)');
            tags.add(MetadataTag.binary(CommonTags.albumArt, thumbnailBytes));
          }
        } catch (e) {
          _logger?.warn('[FP] Failed to add thumbnail: $e');
        }

        _logger?.log('[FP] Writing ${tags.length} tags including custom tags');
        await tagger.writeTags(download.filePath, tags);
        _logger?.log('[FP] Successfully wrote metadata to: ${download.title}');
      } else {
        _logger
            ?.warn('[FP] No blog post data available for: ${download.title}');
      }
    } catch (e) {
      _logger?.error('[FP] Error writing metadata: $e');
    }

    // Remove from downloads queue
    await _db!.delete('FPDownloads', where: 'id = ?', whereArgs: [download.id]);
    _queue.removeWhere((d) => d.id == download.id);
  }

  Future<void> _startWorker(FPDownloadTask download) async {
    if (_activeWorkers.containsKey(download.id)) return;

    _logger?.log('[FP] Starting worker for: ${download.title}');

    download.state = FPDownloadState.downloading;

    await _db!.update(
      'FPDownloads',
      {'state': download.state.index},
      where: 'id = ?',
      whereArgs: [download.id],
    );

    final workerReceivePort = ReceivePort();
    final isolate = await Isolate.spawn(_fpWorkerEntryPoint, {
      'sendPort': workerReceivePort.sendPort,
      'download': download.toSQL(),
      'settings': settings,
      'rootIsolateToken': rootIsolateToken,
    });

    final worker = _FPWorkerHandle(
      isolate: isolate,
      receivePort: workerReceivePort,
      download: download,
    );

    _activeWorkers[download.id] = worker;

    workerReceivePort.listen((msg) {
      if (msg is Map<String, dynamic>) {
        _handleWorkerMessage(download.id, msg);
      }
    });
  }

  void _handleWorkerMessage(int downloadId, Map<String, dynamic> msg) {
    final type = msg['type'] as String;

    switch (type) {
      case 'progress':
        final download = _queue.firstWhere((d) => d.id == downloadId);
        download.received = msg['received'] as int;
        download.filesize = msg['total'] as int;
        break;

      case 'stateChange':
        final download = _queue.firstWhere((d) => d.id == downloadId);
        final oldState = download.state;
        download.state = FPDownloadState.values[msg['state'] as int];

        if (download.state == FPDownloadState.done &&
            oldState != FPDownloadState.done) {
          _logger?.log('[FP] Download completed: ${download.title}');
          // Reset backoff on success
          _currentBackoff = _minBackoff;
          _sendResponse(
            FPIsolateResponse(
              type: 'downloadComplete',
              data: {
                'id': download.id,
                'attachmentId': download.attachmentId,
                'title': download.title,
              },
            ),
          );
        } else if (download.state == FPDownloadState.rateLimited) {
          _logger?.log('[FP] Rate limited: ${download.title}');
          // Set retry time with exponential backoff
          download.retryAfter = DateTime.now().add(_currentBackoff);
          download.retryCount++;

          // Increase backoff for next time
          _currentBackoff = Duration(
            milliseconds: (_currentBackoff.inMilliseconds * 1.5).toInt(),
          );
          if (_currentBackoff > _maxBackoff) {
            _currentBackoff = _maxBackoff;
          }

          _sendResponse(
            FPIsolateResponse(
              type: 'rateLimited',
              data: {
                'id': download.id,
                'retryAfter': download.retryAfter?.toIso8601String(),
              },
            ),
          );
        } else if (download.state == FPDownloadState.expired) {
          _logger?.log('[FP] URL expired: ${download.title}');
          // Notify main isolate that URL needs refresh
          _sendResponse(
            FPIsolateResponse(
              type: 'urlExpired',
              data: {
                'id': download.id,
                'attachmentId': download.attachmentId,
                'qualityLabel': download.qualityLabel,
                'whitelabel': download.whitelabel,
                'title': download.title,
              },
            ),
          );
        } else if (download.state == FPDownloadState.error) {
          _logger?.error('[FP] Download failed: ${download.title}');
          _sendResponse(
            FPIsolateResponse(
              type: 'downloadError',
              data: {
                'id': download.id,
                'attachmentId': download.attachmentId,
              },
            ),
          );
        }

        if (download.state == FPDownloadState.done ||
            download.state == FPDownloadState.rateLimited ||
            download.state == FPDownloadState.error) {
          _updateQueue();
          _sendDownloadsList();
        }
        break;

      case 'log':
        _logger?.log(msg['message'] as String);
        break;

      case 'error':
        _logger?.error(msg['message'] as String);
        break;
    }
  }

  void _sendProgressUpdate() {
    if (_activeWorkers.isEmpty) return;

    final downloads =
        _activeWorkers.values.map((w) => w.download.toMap()).toList();

    _sendResponse(
      FPIsolateResponse(type: 'progress', data: {'downloads': downloads}),
    );
  }

  void _sendStateUpdate() {
    final queueSize =
        _queue.where((d) => d.state == FPDownloadState.none).length;
    final rateLimited =
        _queue.where((d) => d.state == FPDownloadState.rateLimited).length;

    _sendResponse(
      FPIsolateResponse(
        type: 'stateChange',
        data: {
          'running': _running,
          'queueSize': queueSize,
          'activeDownloads': _activeWorkers.length,
          'rateLimited': rateLimited,
        },
      ),
    );
  }

  void _sendDownloadsList() {
    _sendResponse(
      FPIsolateResponse(
        type: 'downloadsList',
        data: {'downloads': _queue.map((d) => d.toMap()).toList()},
      ),
    );
  }

  void _sendResponse(FPIsolateResponse response) {
    mainSendPort.send(response.toJson());
  }
}

/// Handle for active worker isolate
class _FPWorkerHandle {
  final Isolate isolate;
  final ReceivePort receivePort;
  final FPDownloadTask download;

  _FPWorkerHandle({
    required this.isolate,
    required this.receivePort,
    required this.download,
  });
}

/// Worker entry point - handles individual download
Future<void> _fpWorkerEntryPoint(Map<String, dynamic> args) async {
  final mainSendPort = args['sendPort'] as SendPort;
  final downloadData = args['download'] as Map<String, dynamic>;
  final settingsData = args['settings'] as Map<String, dynamic>;
  final rootIsolateToken = args['rootIsolateToken'] as RootIsolateToken;

  BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);

  final download = FPDownloadTask.fromSQL(downloadData);
  final worker = _FPDownloadWorker(
    sendPort: mainSendPort,
    download: download,
    settings: settingsData,
  );

  await worker.execute();
}

/// Worker that executes the download
class _FPDownloadWorker {
  final SendPort sendPort;
  final FPDownloadTask download;
  final Map<String, dynamic> settings;

  _FPDownloadWorker({
    required this.sendPort,
    required this.download,
    required this.settings,
  });

  void _log(String message) {
    sendPort.send({'type': 'log', 'message': '[FP Worker] $message'});
  }

  void _error(String message) {
    sendPort.send({'type': 'error', 'message': '[FP Worker] $message'});
  }

  void _updateState(FPDownloadState state) {
    download.state = state;
    sendPort.send({'type': 'stateChange', 'state': state.index});
  }

  void _updateProgress(int received, int total) {
    sendPort.send({'type': 'progress', 'received': received, 'total': total});
  }

  Future<void> execute() async {
    try {
      _log('Starting download: ${download.title}');

      // Check if URL is expired before attempting download
      if (_isUrlExpired(download.downloadUrl)) {
        _log('Download URL is expired, needs refresh');
        _updateState(FPDownloadState.expired);
        return;
      }

      // Create output directory
      final finalFile = File(download.filePath);
      final partFile = File('${download.filePath}.part');
      await finalFile.parent.create(recursive: true);

      // Parse the download URL (pre-authenticated with token)
      final uri = Uri.parse(download.downloadUrl);
      _log('Download URL: ${uri.toString()}');

      // Create HTTP client
      final client = http.Client();

      try {
        // Check if we can resume from partial file
        int startByte = 0;
        if (await partFile.exists() && download.downloaded > 0) {
          startByte = download.downloaded;
          _log('Resuming from byte: $startByte');
        }

        // Make request with range header for resume
        final request = http.Request('GET', uri);
        request.headers['User-Agent'] = settings['userAgent'] ?? 'FloatyClient';

        if (startByte > 0) {
          request.headers['Range'] = 'bytes=$startByte-';
        }

        final response = await client.send(request);

        // Check for rate limit (error code 1015)
        if (response.statusCode == 429 ||
            response.headers['cf-mitigated'] == 'challenge') {
          _log('Rate limited by API');
          _updateState(FPDownloadState.rateLimited);
          return;
        }

        // Check for 403 Forbidden (likely expired token)
        if (response.statusCode == 403) {
          _log('403 Forbidden - URL likely expired');
          _log('Response headers: ${response.headers}');

          // Log the URL expiry time for diagnostics
          final expiry =
              FPDownloadUrlHelper.getExpiryTime(download.downloadUrl);
          if (expiry != null) {
            final now = DateTime.now();
            final diff = expiry.difference(now);
            _log(
                'URL expiry check: expires in ${diff.inSeconds}s (expiry=$expiry, now=$now)');
          } else {
            _log('URL has no expiry parameter');
          }

          _updateState(FPDownloadState.expired);
          return;
        }

        // Check response body for rate limit error
        if (response.statusCode != 200 && response.statusCode != 206) {
          final body = await response.stream.bytesToString();
          if (body.contains('error code: 1015') || body.contains('429')) {
            _log('Rate limited: $body');
            _updateState(FPDownloadState.rateLimited);
            return;
          }
          _error('HTTP error body: $body');
          _error('HTTP error: ${response.statusCode}');
          _updateState(FPDownloadState.error);
          return;
        }

        // Get total file size
        int totalBytes = 0;
        if (response.headers.containsKey('content-length')) {
          totalBytes = int.parse(response.headers['content-length']!);
        }
        if (response.headers.containsKey('content-range')) {
          // Parse total from "bytes 0-1234/5678"
          final range = response.headers['content-range']!;
          final match = RegExp(r'/(\d+)').firstMatch(range);
          if (match != null) {
            totalBytes = int.parse(match.group(1)!);
          }
        }

        _log('Total bytes: $totalBytes');

        // Open partial file for writing
        final sink = partFile.openWrite(
          mode: startByte > 0 ? FileMode.append : FileMode.write,
        );

        int received = startByte;
        final stopwatch = Stopwatch()..start();
        int lastProgressUpdate = 0;

        try {
          await for (final chunk in response.stream) {
            sink.add(chunk);
            received += chunk.length;

            // Update progress every 100ms
            if (stopwatch.elapsedMilliseconds - lastProgressUpdate > 100) {
              _updateProgress(received, totalBytes);
              lastProgressUpdate = stopwatch.elapsedMilliseconds;
            }
          }

          await sink.flush();
          await sink.close();

          // Verify download
          final finalSize = await partFile.length();
          if (totalBytes > 0 && finalSize < totalBytes) {
            _error('Incomplete download: $finalSize / $totalBytes');
            download.downloaded = finalSize;
            _updateState(FPDownloadState.error);
            return;
          }

          // Rename .part file to temp location
          final tempFile = await partFile.rename(download.filePath);

          // If external download, move to final location
          if (download.useExternalPath &&
              download.finalFilePath != null &&
              download.finalFilePath != download.filePath) {
            final finalFilePath = download.finalFilePath!;
            _log('Moving external download to final location: $finalFilePath');

            // Create parent directories if needed
            final finalFile = File(finalFilePath);
            await finalFile.parent.create(recursive: true);

            // Move file to final location
            try {
              await tempFile.copy(finalFilePath);
              await tempFile.delete();
              _log('Successfully moved to: $finalFilePath');
            } catch (e) {
              _log('Failed to move file: $e');
              // Keep temp file if move fails
            }
          }

          _log('Download complete: ${download.title}');
          _updateProgress(received, totalBytes);
          _updateState(FPDownloadState.done);
        } catch (e) {
          await sink.close();
          download.downloaded = received;
          _error('Stream error: $e');
          _updateState(FPDownloadState.error);
        }
      } finally {
        client.close();
      }
    } catch (e, stack) {
      _error('Download error: $e\n$stack');
      _updateState(FPDownloadState.error);
    }
  }

  /// Check if the download URL is expired
  bool _isUrlExpired(String url) {
    try {
      final expiry = FPDownloadUrlHelper.getExpiryTime(url);
      final now = DateTime.now();

      if (expiry == null) {
        // No expires param, assume not expired
        _log('[FP] _isUrlExpired: no expiry param found for URL');
        return false;
      }

      // Log expiry vs now for diagnostics
      _log('[FP] _isUrlExpired: expiry=$expiry now=$now');

      // Only consider expired if actually past expiry time (no buffer)
      final isExpired = now.isAfter(expiry);
      if (isExpired) {
        final diff = now.difference(expiry);
        _log('[FP] _isUrlExpired: URL expired ${diff.inSeconds}s ago');
      } else {
        final diff = expiry.difference(now);
        _log('[FP] _isUrlExpired: URL valid for ${diff.inSeconds}s more');
      }
      return isExpired;
    } catch (e) {
      _log('[FP] _isUrlExpired: error parsing URL: $e');
      return false;
    }
  }
}
