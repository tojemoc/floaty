import 'dart:async';

import 'package:floaty/features/router/views/root_layout.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:filesize/filesize.dart';

import 'package:floaty/features/download/controllers/fp_download_service.dart';
import 'package:floaty/features/download/models/fp_download.dart';

class FPDownloadsScreen extends StatefulWidget {
  final bool embedded;

  const FPDownloadsScreen({super.key, this.embedded = false});

  @override
  State<FPDownloadsScreen> createState() => _FPDownloadsScreenState();
}

class _FPDownloadsScreenState extends State<FPDownloadsScreen> {
  List<Map<String, dynamic>> _downloads = [];
  StreamSubscription? _subscription;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDownloads();

    _subscription = fpDownloadService.serviceEvents.listen((event) {
      if (event['type'] == 'downloadsList') {
        setState(() {
          _downloads =
              List<Map<String, dynamic>>.from(event['downloads'] ?? []);
          _isLoading = false;
        });
      } else if (event['type'] == 'progress') {
        final progressData = event['data'] as List?;
        if (progressData != null) {
          setState(() {
            for (var update in progressData) {
              final index =
                  _downloads.indexWhere((d) => d['id'] == update['id']);
              if (index != -1) {
                _downloads[index]['received'] = update['received'];
                _downloads[index]['filesize'] = update['filesize'];
              }
            }
          });
        }
      } else if (event['type'] == 'stateChange') {
        setState(() {});
      }
    });
  }

  void _updateAppBar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      rootLayoutKey.currentState?.setAppBar(
        const Text('Video Downloads'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear completed & failed',
            onPressed: () async {
              await fpDownloadService.removeDownloads(FPDownloadState.error);
              await fpDownloadService.removeDownloads(FPDownloadState.done);
            },
          ),
          IconButton(
            icon: Icon(
              fpDownloadService.running ? Icons.stop : Icons.play_arrow,
            ),
            tooltip: fpDownloadService.running ? 'Stop' : 'Start',
            onPressed: () async {
              if (fpDownloadService.running) {
                await fpDownloadService.stop();
              } else {
                await fpDownloadService.start();
              }
              setState(() {});
            },
          ),
        ],
      );
    });
  }

  void _loadDownloads() {
    setState(() {
      _downloads = fpDownloadService.getDownloads();
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> get _downloading => _downloads
      .where((d) =>
          d['state'] == FPDownloadState.downloading.index ||
          d['state'] == FPDownloadState.post.index)
      .toList();

  List<Map<String, dynamic>> get _queued => _downloads
      .where((d) => d['state'] == FPDownloadState.none.index)
      .toList();

  List<Map<String, dynamic>> get _rateLimited => _downloads
      .where((d) => d['state'] == FPDownloadState.rateLimited.index)
      .toList();

  List<Map<String, dynamic>> get _failed => _downloads
      .where((d) => d['state'] == FPDownloadState.error.index)
      .toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _updateAppBar();

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _downloads.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.download_rounded,
                        size: 64,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Downloads',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start downloading videos from posts',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView(
                  children: [
                    // Currently downloading
                    if (_downloading.isNotEmpty) ...[
                      _SectionHeader(
                        title: 'Downloading',
                        count: _downloading.length,
                      ),
                      ..._downloading.map((d) => _DownloadTile(
                            download: d,
                            onRemove: () =>
                                fpDownloadService.removeDownload(d['id']),
                          )),
                    ],

                    // Rate limited
                    if (_rateLimited.isNotEmpty) ...[
                      _SectionHeader(
                        title: 'Rate Limited',
                        count: _rateLimited.length,
                        subtitle: 'Will retry automatically',
                        color: Colors.orange,
                      ),
                      ..._rateLimited.map((d) => _DownloadTile(
                            download: d,
                            onRemove: () =>
                                fpDownloadService.removeDownload(d['id']),
                          )),
                      ListTile(
                        leading: const Icon(Icons.refresh),
                        title: const Text('Retry All Now'),
                        onTap: () => fpDownloadService.retryDownloads(),
                      ),
                    ],

                    // Queued
                    if (_queued.isNotEmpty) ...[
                      _SectionHeader(
                        title: 'Queued',
                        count: _queued.length,
                      ),
                      ..._queued.map((d) => _DownloadTile(
                            download: d,
                            onRemove: () =>
                                fpDownloadService.removeDownload(d['id']),
                          )),
                      ListTile(
                        leading: const Icon(Icons.clear_all),
                        title: const Text('Clear Queue'),
                        onTap: () => fpDownloadService
                            .removeDownloads(FPDownloadState.none),
                      ),
                    ],

                    // Failed
                    if (_failed.isNotEmpty) ...[
                      _SectionHeader(
                        title: 'Failed',
                        count: _failed.length,
                        color: Colors.red,
                      ),
                      ..._failed.map((d) => _DownloadTile(
                            download: d,
                            onRemove: () =>
                                fpDownloadService.removeDownload(d['id']),
                          )),
                      ListTile(
                        leading: const Icon(Icons.refresh),
                        title: const Text('Retry Failed'),
                        onTap: () => fpDownloadService.retryDownloads(),
                      ),
                      ListTile(
                        leading: const Icon(Icons.delete),
                        title: const Text('Clear Failed'),
                        onTap: () => fpDownloadService
                            .removeDownloads(FPDownloadState.error),
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final String? subtitle;
  final Color? color;

  const _SectionHeader({
    required this.title,
    required this.count,
    this.subtitle,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: color ?? theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (color ?? theme.colorScheme.primary).withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  count.toString(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color ?? theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
        ],
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  final Map<String, dynamic> download;
  final VoidCallback onRemove;

  const _DownloadTile({
    required this.download,
    required this.onRemove,
  });

  Widget _buildTrailing(BuildContext context) {
    final state = FPDownloadState.values[download['state'] as int];
    Theme.of(context);

    switch (state) {
      case FPDownloadState.none:
        return const Icon(Icons.query_builder);
      case FPDownloadState.downloading:
        return const Icon(Icons.download_rounded);
      case FPDownloadState.post:
        return const Icon(Icons.miscellaneous_services);
      case FPDownloadState.done:
        return const Icon(Icons.done, color: Colors.green);
      case FPDownloadState.rateLimited:
        return Icon(Icons.schedule, color: Colors.orange[700]);
      case FPDownloadState.error:
        return const Icon(Icons.error, color: Colors.red);
      case FPDownloadState.expired:
        return const Icon(Icons.timer, color: Colors.red);
    }
  }

  String _buildSubtitle() {
    final state = FPDownloadState.values[download['state'] as int];
    final quality = download['qualityLabel'] ?? '';
    final creator = download['creatorName'] ?? '';
    final isOffline = _isOfflineDownload();

    String subtitle = '';
    if (creator.isNotEmpty) {
      subtitle = creator;
    }
    if (quality.isNotEmpty) {
      subtitle += subtitle.isNotEmpty ? ' • $quality' : quality;
    }

    // Add storage location indicator
    subtitle += subtitle.isNotEmpty
        ? (isOffline ? ' • Offline Library' : ' • Downloads')
        : (isOffline ? 'Offline Library' : 'Downloads');

    if (state == FPDownloadState.downloading) {
      final received = download['received'] as int? ?? 0;
      final filesizeint = download['filesize'] as int? ?? 0;
      if (filesizeint > 0) {
        final progress = (received / filesizeint * 100).toStringAsFixed(1);
        subtitle +=
            ' • ${filesize(received)} / ${filesize(filesizeint)} ($progress%)';
      }
    } else if (state == FPDownloadState.rateLimited) {
      subtitle += ' • Will retry automatically';
    } else if (state == FPDownloadState.error) {
      subtitle += ' • Download failed';
    }

    return subtitle;
  }

  bool _isOfflineDownload() {
    final filePath = download['filePath'] as String?;
    if (filePath == null) return false;

    // Check if path contains 'floatplane_offline' (app's offline storage)
    return filePath.contains('floatplane_offline');
  }

  @override
  Widget build(BuildContext context) {
    final state = FPDownloadState.values[download['state'] as int];
    final theme = Theme.of(context);
    final isOffline = _isOfflineDownload();

    return Column(
      children: [
        ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 64,
              height: 36,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: download['thumbnailPath'] != null &&
                            (download['thumbnailPath'] as String).isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: download['thumbnailPath'],
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.video_library, size: 20),
                            ),
                          )
                        : Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.video_library, size: 20),
                          ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: isOffline
                            ? Colors.blue.withValues(alpha: 0.9)
                            : Colors.green.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Icon(
                        isOffline ? Icons.phone_android : Icons.folder,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          title: Text(
            download['title'] ?? 'Unknown',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            _buildSubtitle(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: _buildTrailing(context),
          onTap: () {
            if (state != FPDownloadState.downloading &&
                state != FPDownloadState.post) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Remove Download'),
                  content: const Text('Remove this download from the queue?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onRemove();
                      },
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              );
            }
          },
        ),
        if (state == FPDownloadState.downloading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(
              value: _getProgress(),
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
            ),
          ),
      ],
    );
  }

  double _getProgress() {
    final received = download['received'] as int? ?? 0;
    final filesize = download['filesize'] as int? ?? 1;
    if (filesize <= 0) return 0;
    return received / filesize;
  }
}
