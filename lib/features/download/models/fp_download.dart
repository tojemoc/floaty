import 'dart:convert';
import 'package:floaty/features/api/models/definitions.dart';
import 'package:flutter/foundation.dart';

/// Download state for Floatplane downloads
enum FPDownloadState {
  none, // Queued, not started
  downloading, // Currently downloading
  post, // Post-processing (if needed)
  done, // Completed successfully
  rateLimited, // Rate limited by API (error code 1015)
  expired, // Download URL expired, needs refresh
  error, // General error
}

/// Model for a Floatplane video/audio download task
class FPDownloadTask {
  int id;
  String postId; // Blog post ID
  String attachmentId; // Video/Audio attachment ID
  String attachmentType; // 'video' or 'audio'
  String title;
  String? creatorName;
  String? channelName;
  String thumbnailPath;
  String qualityLabel; // e.g., '1080p', '720p'
  String downloadUrl; // Direct download URL from delivery API
  String filePath; // Local file path (temp location during download)
  String? finalFilePath; // Final destination path (for external downloads)
  bool useExternalPath; // Whether this is an external download
  double duration; // Duration in seconds
  FPDownloadState state;
  String whitelabel;

  // Full blog post data for metadata tagging
  ContentPostV3Response? blogPost;

  // Dynamic progress
  int received = 0;
  int filesize = 0;
  int downloaded = 0; // Bytes already downloaded (for resume)

  // Metadata for offline playback (legacy - redundant with blogPost)
  String? postTitle;
  String? postDescription;
  DateTime? releaseDate;

  // Rate limit handling
  DateTime? retryAfter; // When to retry after rate limit
  int retryCount = 0;

  FPDownloadTask({
    required this.id,
    required this.postId,
    required this.attachmentId,
    required this.attachmentType,
    required this.title,
    this.creatorName,
    this.channelName,
    required this.thumbnailPath,
    required this.qualityLabel,
    required this.downloadUrl,
    required this.filePath,
    this.finalFilePath,
    this.useExternalPath = false,
    required this.duration,
    required this.state,
    required this.whitelabel,
    this.blogPost,
    this.postTitle,
    this.postDescription,
    this.releaseDate,
    this.retryAfter,
    this.retryCount = 0,
  });

  factory FPDownloadTask.fromSQL(Map<String, dynamic> row) {
    ContentPostV3Response? blogPost;
    final blogPostJson = row['blogPostJson'];

    if (blogPostJson != null) {
      try {
        final json = jsonDecode(blogPostJson);
        blogPost = ContentPostV3Response.fromJson(json);
      } catch (e) {
        debugPrint('[FP] Error parsing blogPostJson: $e');
      }
    } else {
      debugPrint('[FP] No blogPostJson in database for: ${row['title']}');
    }

    return FPDownloadTask(
      id: row['id'],
      postId: row['postId'],
      attachmentId: row['attachmentId'],
      attachmentType: row['attachmentType'],
      title: row['title'],
      creatorName: row['creatorName'],
      channelName: row['channelName'],
      thumbnailPath: row['thumbnailPath'],
      qualityLabel: row['qualityLabel'],
      downloadUrl: row['downloadUrl'],
      filePath: row['filePath'],
      finalFilePath: row['finalFilePath'],
      useExternalPath: (row['useExternalPath'] as int?) == 1,
      duration: row['duration']?.toDouble() ?? 0.0,
      state: FPDownloadState.values[row['state']],
      whitelabel: row['whitelabel'],
      blogPost: blogPost,
      postTitle: row['postTitle'],
      postDescription: row['postDescription'],
      releaseDate: row['releaseDate'] != null
          ? DateTime.tryParse(row['releaseDate'])
          : null,
      retryAfter: row['retryAfter'] != null
          ? DateTime.tryParse(row['retryAfter'])
          : null,
      retryCount: row['retryCount'] ?? 0,
    )..downloaded = row['downloaded'] ?? 0;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'postId': postId,
      'attachmentId': attachmentId,
      'attachmentType': attachmentType,
      'title': title,
      'creatorName': creatorName,
      'channelName': channelName,
      'thumbnailPath': thumbnailPath,
      'qualityLabel': qualityLabel,
      'filePath': filePath,
      'duration': duration,
      'state': state.index,
      'whitelabel': whitelabel,
      'received': received,
      'filesize': filesize,
    };
  }

  Map<String, dynamic> toSQL() {
    return {
      'id': id,
      'postId': postId,
      'attachmentId': attachmentId,
      'attachmentType': attachmentType,
      'title': title,
      'creatorName': creatorName,
      'channelName': channelName,
      'thumbnailPath': thumbnailPath,
      'qualityLabel': qualityLabel,
      'downloadUrl': downloadUrl,
      'filePath': filePath,
      'finalFilePath': finalFilePath,
      'useExternalPath': useExternalPath ? 1 : 0,
      'duration': duration,
      'state': state.index,
      'whitelabel': whitelabel,
      'blogPostJson': blogPost != null ? jsonEncode(blogPost!.toJson()) : null,
      'postTitle': postTitle,
      'postDescription': postDescription,
      'releaseDate': releaseDate?.toIso8601String(),
      'retryAfter': retryAfter?.toIso8601String(),
      'retryCount': retryCount,
      'downloaded': downloaded,
    };
  }

  double get progress {
    if (filesize <= 0) return 0.0;
    return received / filesize;
  }

  bool get isRateLimited => state == FPDownloadState.rateLimited;

  bool get canRetry {
    if (retryAfter == null) return true;
    return DateTime.now().isAfter(retryAfter!);
  }

  /// Create from post and attachment data
  static FPDownloadTask fromPostAndAttachment({
    required ContentPostV3Response post,
    required dynamic attachment, // VideoAttachmentModel or AudioAttachmentModel
    required String qualityLabel,
    required String downloadUrl,
    required String filePath,
    required String whitelabel,
    String? creatorName,
    String? channelName,
  }) {
    final isVideo = attachment is VideoAttachmentModel;

    return FPDownloadTask(
      id: 0, // Will be set by database
      postId: post.id ?? '',
      attachmentId:
          isVideo ? (attachment).id : (attachment as AudioAttachmentModel).id,
      attachmentType: isVideo ? 'video' : 'audio',
      title: isVideo
          ? (attachment).title
          : (attachment as AudioAttachmentModel).title,
      creatorName: creatorName ?? post.creator?.title,
      channelName: channelName ?? post.channel?.title,
      thumbnailPath: isVideo
          ? (attachment).thumbnail.path ?? ''
          : post.thumbnail?.path ?? '',
      qualityLabel: qualityLabel,
      downloadUrl: downloadUrl,
      filePath: filePath,
      duration: isVideo
          ? (attachment).duration
          : (attachment as AudioAttachmentModel).duration.toDouble(),
      state: FPDownloadState.none,
      whitelabel: whitelabel,
      blogPost: post,
      postTitle: post.title,
      postDescription: post.text,
      releaseDate: post.releaseDate,
    );
  }
}
