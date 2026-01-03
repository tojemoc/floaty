import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:filesize/filesize.dart';
import 'package:floaty/features/router/views/root_layout.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:metatagger/metatagger.dart';

import 'package:floaty/features/download/controllers/fp_download_service.dart';
import 'package:floaty/features/api/models/definitions.dart';

class FPOfflineLibraryScreen extends StatefulWidget {
  final bool embedded;

  const FPOfflineLibraryScreen({super.key, this.embedded = false});

  @override
  State<FPOfflineLibraryScreen> createState() => _FPOfflineLibraryScreenState();
}

class _FPOfflineLibraryScreenState extends State<FPOfflineLibraryScreen> {
  List<Map<String, dynamic>> _content = [];
  bool _isLoading = true;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  void _updateAppBar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      rootLayoutKey.currentState?.setAppBar(
        Row(
          children: [
            const Text('Offline Videos'),
            if (_isScanning) ...[
              const SizedBox(width: 12),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isScanning ? null : _loadContent,
            tooltip: 'Refresh',
          ),
          if (_content.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () {
                final totalSize = _content.fold<int>(
                    0, (sum, c) => sum + (c['fileSize'] as int? ?? 0));
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Offline Storage'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Videos: ${_content.length}'),
                        Text('Total Size: ${filesize(totalSize)}'),
                        const SizedBox(height: 8),
                        Text(
                          'Location: ${fpDownloadService.offlinePath ?? "Unknown"}',
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      );
    });
  }

  Future<void> _loadContent() async {
    if (!mounted) return;

    // Load cached content first
    final cachedContent = await _loadCachedContent();
    if (cachedContent.isNotEmpty && mounted) {
      setState(() {
        _content = cachedContent;
        _isLoading = false;
        _isScanning = true; // Show that we're updating in background
      });
    } else {
      setState(() {
        _isLoading = true;
      });
    }

    // Scan directory in background to update cache
    try {
      final offlinePath = fpDownloadService.offlinePath;
      if (offlinePath == null || offlinePath.isEmpty) {
        if (!mounted) return;
        setState(() {
          _content = [];
          _isLoading = false;
          _isScanning = false;
        });
        return;
      }

      final results = await _scanOfflineDirectory(offlinePath);

      // Save to cache
      await _saveCachedContent(results);

      if (!mounted) return;
      setState(() {
        _content = results;
        _isLoading = false;
        _isScanning = false;
      });
    } catch (e) {
      debugPrint('[FP] Error loading offline content: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isScanning = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadCachedContent() async {
    try {
      final box = await Hive.openBox('offline_library_cache');
      final cached = box.get('content');
      if (cached is List) {
        debugPrint('[FP] Loaded ${cached.length} items from cache');
        return List<Map<String, dynamic>>.from(
            cached.map((item) => Map<String, dynamic>.from(item as Map)));
      }
    } catch (e) {
      debugPrint('[FP] Error loading cache: $e');
    }
    return [];
  }

  Future<void> _saveCachedContent(List<Map<String, dynamic>> content) async {
    try {
      final box = await Hive.openBox('offline_library_cache');
      await box.put('content', content);
      debugPrint('[FP] Saved ${content.length} items to cache');
    } catch (e) {
      debugPrint('[FP] Error saving cache: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _scanOfflineDirectory(
      String dirPath) async {
    final results = <Map<String, dynamic>>[];
    final tagger = MetaTagger();

    debugPrint('[FP] Scanning offline directory: $dirPath');

    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        debugPrint('[FP] Directory does not exist: $dirPath');
        return results;
      }

      int fileCount = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          final path = entity.path.toLowerCase();
          // Skip .part files
          if (path.endsWith('.part')) continue;

          if (path.endsWith('.mp4') || path.endsWith('.mp3')) {
            fileCount++;
            debugPrint('[FP] Found media file: ${entity.path}');
            try {
              final tags = await tagger.readTags(entity.path);
              debugPrint('[FP] Read ${tags.length} tags from file');

              if (tags.isEmpty) {
                debugPrint('[FP] No tags found in file');
                continue;
              }

              // Build a map from tags
              final tagMap = <String, String>{};
              for (final tag in tags) {
                if (tag.type == TagType.text) {
                  tagMap[tag.key] = tag.value.toString();
                  debugPrint('[FP] Tag: ${tag.key}');
                }
              }

              // Check if this is a Floatplane offline file
              if (!tagMap.containsKey('FP_BLOGPOST_DATA')) {
                debugPrint('[FP] Missing FP_BLOGPOST_DATA tag');
                continue;
              }

              debugPrint('[FP] Found Floatplane offline video');

              // Store the JSON string directly, not the parsed object
              // This ensures proper serialization of nested objects
              final blogPostJsonString = tagMap['FP_BLOGPOST_DATA']!;
              final fileSize = await entity.length();

              results.add({
                'blogPostJson': blogPostJsonString, // Store as JSON string
                'attachmentId': tagMap['FP_ATTACHMENT_ID'] ?? '',
                'qualityLabel': tagMap['FP_QUALITY'] ?? 'Unknown',
                'whitelabel': tagMap['FP_WHITELABEL'] ?? 'floatplane',
                'downloadedAt': tagMap['FP_DOWNLOADED_AT'] ??
                    DateTime.now().toIso8601String(),
                'filePath': entity.path,
                'fileSize': fileSize,
              });
            } catch (e) {
              debugPrint('[FP] Error reading metadata from ${entity.path}: $e');
            }
          }
        }
      }

      debugPrint(
          '[FP] Scanned $fileCount media files, found ${results.length} offline videos');
    } catch (e) {
      debugPrint('[FP] Error scanning directory: $e');
    }

    return results;
  }

  String _formatDuration(double seconds) {
    final duration = Duration(seconds: seconds.toInt());
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${secs}s';
    } else {
      return '${secs}s';
    }
  }

  Future<void> _deleteContent(Map<String, dynamic> content) async {
    String title = 'Unknown';
    try {
      final blogPostJsonString = content['blogPostJson'] as String?;
      if (blogPostJsonString != null) {
        final blogPostJson = jsonDecode(blogPostJsonString);
        title = blogPostJson['title'] as String? ?? 'Unknown';
      }
    } catch (e) {
      debugPrint('[FP] Error parsing title: $e');
    }

    final filePath = content['filePath'] as String;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Offline Video'),
        content: Text(
            'Are you sure you want to delete "$title"?\n\nThis will remove the downloaded file.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }

        // Update cache by removing the deleted item
        _content.removeWhere((c) => c['filePath'] == filePath);
        await _saveCachedContent(_content);

        // Reload content to rescan directory
        _loadContent();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Deleted "$title"')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }

  void _playContent(Map<String, dynamic> content) {
    try {
      final blogPostJsonString = content['blogPostJson'] as String?;
      if (blogPostJsonString == null) {
        debugPrint('[FP] No blogPostJson found in content');
        return;
      }

      final blogPostJson = jsonDecode(blogPostJsonString);
      final blogPost = ContentPostV3Response.fromJson(blogPostJson);
      final postId = blogPost.id;
      final attachmentId = content['attachmentId'] as String;
      final filePath = content['filePath'] as String;

      debugPrint('[FP] Playing offline video: $postId');

      // Navigate to post with offline data
      context.push('/post/$postId', extra: {
        'isOffline': true,
        'offlinePost': blogPost,
        'offlineAttachmentId': attachmentId,
        'offlineFilePath': filePath,
      });
    } catch (e) {
      debugPrint('[FP] Error playing offline content: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to play offline video: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _updateAppBar();

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _content.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.download_done_rounded,
                        size: 64,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Offline Videos',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Downloaded videos will appear here',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _content.length,
                  itemBuilder: (context, index) {
                    final content = _content[index];
                    return _OfflineContentTile(
                      content: content,
                      onPlay: () => _playContent(content),
                      onDelete: () => _deleteContent(content),
                      formatDuration: _formatDuration,
                    );
                  },
                ),
    );
  }
}

class _OfflineContentTile extends StatelessWidget {
  final Map<String, dynamic> content;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  final String Function(double) formatDuration;

  const _OfflineContentTile({
    required this.content,
    required this.onPlay,
    required this.onDelete,
    required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Parse blogPost from JSON string
    final blogPostJsonString = content['blogPostJson'] as String?;
    ContentPostV3Response? blogPost;
    if (blogPostJsonString != null) {
      try {
        final blogPostJson = jsonDecode(blogPostJsonString);
        blogPost = ContentPostV3Response.fromJson(blogPostJson);
        debugPrint('[FP] Parsed blog post: ${blogPost.title}');
      } catch (e) {
        debugPrint('[FP] Error parsing blog post: $e');
      }
    } else {
      debugPrint('[FP] No blogPostJson in content map');
    }

    // Extract fields from blogPost and metadata
    final title = blogPost?.title ?? 'Unknown';
    final thumbnailPath = blogPost?.thumbnail?.path ?? '';
    final creatorName = blogPost?.creator?.title ?? 'Unknown Creator';
    final qualityLabel = content['qualityLabel'] as String? ?? 'Unknown';
    final fileSize = content['fileSize'] as int? ?? 0;

    debugPrint('[FP] Displaying: title=$title, creator=$creatorName');

    // Get duration from video/audio attachment
    double duration = 0.0;
    if (blogPost != null) {
      final attachmentId = content['attachmentId'] as String;
      // Find the attachment in the blogPost
      for (final attachment in blogPost.videoAttachments) {
        if (attachment.id == attachmentId) {
          duration = attachment.duration;
          break;
        }
      }
      if (duration == 0.0) {
        for (final attachment in blogPost.audioAttachments) {
          if (attachment.id == attachmentId) {
            duration = attachment.duration.toDouble();
            break;
          }
        }
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: onPlay,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    SizedBox(
                      width: 120,
                      height: 68,
                      child: thumbnailPath.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: thumbnailPath,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                child: const Center(
                                  child: Icon(Icons.video_library),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                child: const Center(
                                  child: Icon(Icons.video_library),
                                ),
                              ),
                            )
                          : Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Center(
                                child: Icon(Icons.video_library),
                              ),
                            ),
                    ),
                    // Duration badge
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          formatDuration(duration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    // Offline badge
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.download_done,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Content info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      creatorName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          qualityLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          filesize(fileSize),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Actions
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.play_circle_filled),
                    iconSize: 32,
                    color: theme.colorScheme.primary,
                    onPressed: onPlay,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    iconSize: 20,
                    color: theme.colorScheme.error,
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
