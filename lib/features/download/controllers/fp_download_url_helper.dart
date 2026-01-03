import 'dart:convert';

import 'package:floaty/features/api/repositories/fpapi.dart';
import 'package:floaty/features/download/controllers/fp_rate_limit_manager.dart';
import 'package:logging/logging.dart';

/// Helper for managing download URL expiry and refresh
class FPDownloadUrlHelper {
  static final Logger _log = Logger('FPDownloadUrlHelper');

  /// Check if a download URL is expired
  static bool isUrlExpired(String url) {
    try {
      final uri = Uri.parse(url);
      final expiresParam = uri.queryParameters['expires'];

      if (expiresParam == null) {
        // No expires param, assume not expired
        return false;
      }

      final expiresEpoch = int.tryParse(expiresParam);
      if (expiresEpoch == null) return false;

      final expiresAt =
          DateTime.fromMillisecondsSinceEpoch(expiresEpoch * 1000);
      final now = DateTime.now();

      // Consider expired if within 1 minute of expiry
      return now.isAfter(expiresAt.subtract(const Duration(minutes: 1)));
    } catch (e) {
      _log.warning('Error checking URL expiry: $e');
      return false;
    }
  }

  /// Get expiry time from URL
  static DateTime? getExpiryTime(String url) {
    try {
      final uri = Uri.parse(url);
      final expiresParam = uri.queryParameters['expires'];

      if (expiresParam == null) return null;

      final expiresEpoch = int.tryParse(expiresParam);
      if (expiresEpoch == null) return null;

      return DateTime.fromMillisecondsSinceEpoch(expiresEpoch * 1000);
    } catch (e) {
      return null;
    }
  }

  /// Refresh a download URL by fetching new delivery info
  /// Returns the new URL or null if rate limited or failed
  static Future<RefreshResult> refreshDownloadUrl({
    required String attachmentId,
    required String attachmentTitle,
    required String qualityLabel,
    required String whitelabel,
  }) async {
    try {
      // Attempt the delivery request even if local counters indicate a rate limit.
      final deliveryResponse = await fpApiRequests.getDelivery(
        whitelabel,
        'download',
        attachmentId,
      );

      final response = deliveryResponse['body'] as String;
      final headers = deliveryResponse['headers'] as Map<String, String>;
      final statusCode = deliveryResponse['statusCode'] as int;

      // If server indicates rate limiting, honor it and return the retry-after
      if (statusCode == 429 || response.contains('error code: 1015')) {
        final retryAfter =
            fpRateLimitManager.parseRetryAfter(headers, response);
        fpRateLimitManager.setRateLimited(retryAfter);
        return RefreshResult(
          success: false,
          isRateLimited: true,
          secondsUntilRetry: retryAfter,
        );
      }

      if (response.isEmpty) {
        return RefreshResult(success: false, error: 'Empty response');
      }

      // Record successful request locally so counters stay accurate
      fpRateLimitManager.recordRequest();

      final decoded = jsonDecode(response);
      final newUrl = _parseDownloadUrl(decoded, attachmentTitle, qualityLabel);

      if (newUrl == null) {
        return RefreshResult(success: false, error: 'Could not parse new URL');
      }

      return RefreshResult(success: true, newUrl: newUrl);
    } catch (e) {
      _log.severe('Error refreshing download URL: $e');
      return RefreshResult(success: false, error: e.toString());
    }
  }

  /// Parse download URL from delivery response
  static String? _parseDownloadUrl(
    Map<String, dynamic> decoded,
    String attachmentTitle,
    String qualityLabel,
  ) {
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

            // Match by quality label
            if (label == qualityLabel) {
              final variantUrl = variant['url'] as String;

              // Convert HLS URL to direct download URL
              String downloadUrl = '$baseUrl$variantUrl';

              // Remove /chunk.m3u8 if present
              if (downloadUrl.contains('/chunk.m3u8')) {
                downloadUrl = downloadUrl.replaceFirst('/chunk.m3u8', '');
              }

              // Remove /Videos/ prefix if present
              downloadUrl = downloadUrl.replaceFirst('/Videos/', '/');

              // Add required download parameters
              final filename = Uri.encodeComponent('$attachmentTitle ($label)');
              downloadUrl += '&attachment=true&filename=$filename';

              return downloadUrl;
            }
          }
        }
      }
    }

    // Fall back to old format (cdn/resource/qualityLevels)
    final cdn = decoded['cdn'] as String?;
    final resource = decoded['resource'] as Map<String, dynamic>?;

    if (cdn != null && resource != null) {
      final data = resource['data'] as Map<String, dynamic>?;
      final qualityLevels = data?['qualityLevels'] as List?;
      final qualityLevelParams =
          data?['qualityLevelParams'] as Map<String, dynamic>?;
      final uri = resource['uri'] as String?;

      if (qualityLevels != null && qualityLevelParams != null && uri != null) {
        for (var quality in qualityLevels) {
          final qualityName = quality['name'] as String;
          final label = quality['label'] as String;

          if (label == qualityLabel) {
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
                return '$cdn$downloadUri&attachment=true&filename=$filename';
              }
            }
          }
        }
      }
    }

    return null;
  }
}

/// Result of URL refresh operation
class RefreshResult {
  final bool success;
  final String? newUrl;
  final bool isRateLimited;
  final int secondsUntilRetry;
  final String? error;

  RefreshResult({
    required this.success,
    this.newUrl,
    this.isRateLimited = false,
    this.secondsUntilRetry = 0,
    this.error,
  });
}
