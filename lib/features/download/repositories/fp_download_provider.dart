import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:floaty/features/api/repositories/fpapi.dart';
import 'package:floaty/features/api/models/definitions.dart';
import 'package:floaty/features/download/controllers/fp_download_service.dart';
import 'package:floaty/features/download/controllers/fp_rate_limit_manager.dart';
import 'package:floaty/whitelabels.dart';
import 'package:flutter_riverpod/legacy.dart';

/// Download destination type
enum FPDownloadDestination {
  offline, // Save to app's offline library
  external, // Save to user-chosen location / downloads folder
}

/// Quality option for download
class FPDownloadOption {
  final String qualityLabel;
  final String url;
  final String? fileSize;
  final String? resolution;

  FPDownloadOption({
    required this.qualityLabel,
    required this.url,
    this.fileSize,
    this.resolution,
  });
}

/// State for download options dialog
class FPDownloadOptionsState {
  final bool isLoading;
  final String? error;
  final List<FPDownloadOption> options;
  final bool isRateLimited;
  final int rateLimitSecondsRemaining;
  final FPDownloadDestination selectedDestination;

  const FPDownloadOptionsState({
    this.isLoading = false,
    this.error,
    this.options = const [],
    this.isRateLimited = false,
    this.rateLimitSecondsRemaining = 0,
    this.selectedDestination = FPDownloadDestination.offline,
  });

  FPDownloadOptionsState copyWith({
    bool? isLoading,
    String? error,
    List<FPDownloadOption>? options,
    bool? isRateLimited,
    int? rateLimitSecondsRemaining,
    FPDownloadDestination? selectedDestination,
  }) {
    return FPDownloadOptionsState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      options: options ?? this.options,
      isRateLimited: isRateLimited ?? this.isRateLimited,
      rateLimitSecondsRemaining:
          rateLimitSecondsRemaining ?? this.rateLimitSecondsRemaining,
      selectedDestination: selectedDestination ?? this.selectedDestination,
    );
  }

  String get formattedTimeRemaining {
    if (rateLimitSecondsRemaining <= 0) return '';
    final minutes = rateLimitSecondsRemaining ~/ 60;
    final seconds = rateLimitSecondsRemaining % 60;
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }
}

/// Provider for managing download options
class FPDownloadOptionsNotifier extends StateNotifier<FPDownloadOptionsState> {
  final Logger _log = Logger('FPDownloadOptionsNotifier');
  Timer? _countdownTimer;
  StreamSubscription? _rateLimitSubscription;
  String? _lastAttachmentId;
  String? _lastAttachmentTitle;

  FPDownloadOptionsNotifier() : super(const FPDownloadOptionsState()) {
    // Listen for rate limit changes
    _rateLimitSubscription =
        fpRateLimitManager.stateStream.listen(_onRateLimitStateChanged);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _rateLimitSubscription?.cancel();
    super.dispose();
  }

  void _onRateLimitStateChanged(RateLimitState rateLimitState) {
    if (rateLimitState.isRateLimited) {
      state = state.copyWith(
        isRateLimited: true,
        rateLimitSecondsRemaining: rateLimitState.secondsRemaining,
        error: 'Rate limited. Please wait...',
      );
    } else if (state.isRateLimited) {
      // Rate limit cleared
      state = state.copyWith(
        isRateLimited: false,
        rateLimitSecondsRemaining: 0,
        error: null,
      );

      // If we previously attempted to fetch options for an attachment and
      // got blocked by rate limiting, automatically retry fetching now that
      // the server-side rate limit has cleared.
      if (_lastAttachmentId != null &&
          state.options.isEmpty &&
          !state.isLoading) {
        fetchDownloadOptions(_lastAttachmentId!, _lastAttachmentTitle ?? '');
      }
    }
  }

  void reset() {
    _countdownTimer?.cancel();
    state = const FPDownloadOptionsState();
  }

  void setLoading() {
    state = const FPDownloadOptionsState(isLoading: true);
  }

  void setDestination(FPDownloadDestination destination) {
    state = state.copyWith(selectedDestination: destination);
  }

  void setError(String error,
      {bool isRateLimited = false, int retryAfter = 0}) {
    _countdownTimer?.cancel();

    state = FPDownloadOptionsState(
      error: error,
      isRateLimited: isRateLimited,
      rateLimitSecondsRemaining: retryAfter,
      selectedDestination: state.selectedDestination,
    );

    if (isRateLimited && retryAfter > 0) {
      _startCountdown(retryAfter);
    }
  }

  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.rateLimitSecondsRemaining > 0) {
        state = state.copyWith(
          rateLimitSecondsRemaining: state.rateLimitSecondsRemaining - 1,
          error: 'Rate limited. Please wait ${state.formattedTimeRemaining}...',
        );
      } else {
        _countdownTimer?.cancel();
        state = state.copyWith(
          isRateLimited: false,
          error: null,
        );
      }
    });
  }

  void setOptions(List<FPDownloadOption> options) {
    state = FPDownloadOptionsState(
      options: options,
      selectedDestination: state.selectedDestination,
    );
  }

  /// Fetch download options from API
  Future<void> fetchDownloadOptions(
      String attachmentId, String attachmentTitle) async {
    // Remember last requested attachment so we can retry after rate-limit clears
    _lastAttachmentId = attachmentId;
    _lastAttachmentTitle = attachmentTitle;
    setLoading();

    try {
      // Attempt the delivery API request even if our local counters indicate a rate
      // limit. We'll only record a successful request locally; if the server
      // responds with 429 we'll parse its retry-after and set the rate-limit state.

      final whitelabel = await whitelabels.getSelectedWhitelabel();
      final deliveryResponse = await fpApiRequests.getDelivery(
        whitelabel.friendlyName,
        'download',
        attachmentId,
      );

      final response = deliveryResponse['body'] as String;
      final headers = deliveryResponse['headers'] as Map<String, String>;
      final statusCode = deliveryResponse['statusCode'] as int;

      _log.info('Download delivery response: $response');

      // If server indicates rate limiting, honor the server-provided retry-after
      if (statusCode == 429 || response.contains('error code: 1015')) {
        final retryAfter =
            fpRateLimitManager.parseRetryAfter(headers, response);
        fpRateLimitManager.setRateLimited(retryAfter);

        final minutes = retryAfter ~/ 60;
        final seconds = retryAfter % 60;
        final timeStr = minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s';

        setError(
          'Rate limited. Please wait $timeStr...',
          isRateLimited: true,
          retryAfter: retryAfter,
        );
        return;
      }

      if (response.isEmpty) {
        setError('Failed to get download info');
        return;
      }

      // Record the successful request so local counters reflect reality
      fpRateLimitManager.recordRequest();

      final decoded = jsonDecode(response);
      final options = <FPDownloadOption>[];

      // Try new format first (groups/origins/variants)
      final groups = decoded['groups'] as List?;
      if (groups != null && groups.isNotEmpty) {
        final group = groups[0] as Map<String, dynamic>;
        final origins = group['origins'] as List?;
        final variants = group['variants'] as List?;

        if (origins != null && origins.isNotEmpty && variants != null) {
          final baseUrl = (origins[0] as Map<String, dynamic>)['url'] as String;

          for (var variant in variants) {
            if (variant['enabled'] == true) {
              final label = variant['label'] as String;
              final variantUrl = variant['url'] as String;

              // Convert HLS URL to direct download URL
              // /Videos/xxx/360.mp4/chunk.m3u8?token=... -> /xxx/360.mp4?token=...
              String downloadUrl = '$baseUrl$variantUrl';

              _log.info('Original download URL: $downloadUrl');

              // Remove /chunk.m3u8 if present
              if (downloadUrl.contains('/chunk.m3u8')) {
                downloadUrl = downloadUrl.replaceFirst('/chunk.m3u8', '');
              }

              // Remove /Videos/ prefix if present
              downloadUrl = downloadUrl.replaceFirst('/Videos/', '/');

              // Add required download parameters
              final filename = Uri.encodeComponent('$attachmentTitle ($label)');
              downloadUrl += '&attachment=true&filename=$filename';

              // Get file size estimate from bitrate and duration if available
              String? fileSize;
              final meta = variant['meta'] as Map<String, dynamic>?;
              if (meta != null) {
                final video = meta['video'] as Map<String, dynamic>?;
                if (video != null) {
                  // We don't have duration here, so just show quality info
                  final width = video['width'] as int? ?? 0;
                  final height = video['height'] as int? ?? 0;
                  fileSize = '${width}x$height';
                }
              }

              options.add(FPDownloadOption(
                qualityLabel: label,
                url: downloadUrl,
                fileSize: fileSize,
              ));
            }
          }
        }
      }

      // Fall back to old format (cdn/resource/qualityLevels)
      if (options.isEmpty) {
        final cdn = decoded['cdn'] as String?;
        final resource = decoded['resource'] as Map<String, dynamic>?;

        if (cdn != null && resource != null) {
          final data = resource['data'] as Map<String, dynamic>?;
          final qualityLevels = data?['qualityLevels'] as List?;
          final qualityLevelParams =
              data?['qualityLevelParams'] as Map<String, dynamic>?;
          final uri = resource['uri'] as String?;

          if (qualityLevels != null &&
              qualityLevelParams != null &&
              uri != null) {
            for (var quality in qualityLevels) {
              final qualityName = quality['name'] as String;
              final qualityLabel = quality['label'] as String;
              final params =
                  qualityLevelParams[qualityName] as Map<String, dynamic>?;

              if (params != null) {
                final videoFile = params['1'] as String?;
                final token = params['2'] as String?;

                if (videoFile != null && token != null) {
                  final downloadUri = uri
                      .replaceFirst('{qualityLevelParams.1}', videoFile)
                      .replaceFirst('{qualityLevelParams.2}', token);

                  // Add required download parameters
                  final filename =
                      Uri.encodeComponent('$attachmentTitle ($qualityLabel)');
                  final downloadUrl =
                      '$cdn$downloadUri&attachment=true&filename=$filename';

                  options.add(FPDownloadOption(
                    qualityLabel: qualityLabel,
                    url: downloadUrl,
                  ));
                }
              }
            }
          }
        }
      }

      if (options.isEmpty) {
        setError('No download options available');
        return;
      }

      setOptions(options);
    } catch (e) {
      setError('Error: $e');
    }
  }

  /// Start download with selected quality
  Future<bool> startDownload({
    required ContentPostV3Response post,
    required dynamic attachment,
    required FPDownloadOption option,
    String? creatorName,
    String? channelName,
    FPDownloadDestination destination = FPDownloadDestination.offline,
  }) async {
    try {
      final whitelabel = await whitelabels.getSelectedWhitelabel();

      await fpDownloadService.addDownload(
        post: post,
        attachment: attachment,
        qualityLabel: option.qualityLabel,
        downloadUrl: option.url,
        whitelabel: whitelabel.friendlyName,
        creatorName: creatorName,
        channelName: channelName,
        useExternalPath: destination == FPDownloadDestination.external,
      );

      return true;
    } catch (e) {
      return false;
    }
  }
}

final fpDownloadOptionsProvider =
    StateNotifierProvider<FPDownloadOptionsNotifier, FPDownloadOptionsState>(
  (ref) => FPDownloadOptionsNotifier(),
);

/// Check if an attachment is available offline
final isOfflineAvailableProvider =
    Provider.family<bool, String>((ref, attachmentId) {
  return fpDownloadService.isAvailableOffline(attachmentId);
});

/// Get offline file path for an attachment
final offlineFilePathProvider =
    Provider.family<String?, String>((ref, attachmentId) {
  return fpDownloadService.getOfflineFilePath(attachmentId);
});
