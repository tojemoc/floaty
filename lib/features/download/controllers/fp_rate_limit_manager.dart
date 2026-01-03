import 'dart:async';

/// Manages Floatplane API rate limits for the delivery API
/// Rate limit: 2 requests per 5 minutes, up to 8 concurrent downloads
class FPRateLimitManager {
  static final FPRateLimitManager _instance = FPRateLimitManager._internal();
  factory FPRateLimitManager() => _instance;
  FPRateLimitManager._internal();

  // Track when we can make the next delivery API request
  DateTime? _rateLimitedUntil;

  // Track recent delivery API requests (within 5 minutes)
  final List<DateTime> _recentRequests = [];

  // Stream for UI updates
  final StreamController<RateLimitState> _stateController =
      StreamController.broadcast();

  Stream<RateLimitState> get stateStream => _stateController.stream;

  /// Maximum delivery API requests per 5 minutes
  static const int maxRequestsPerWindow = 2;

  /// Window duration for rate limit
  static const Duration rateLimitWindow = Duration(minutes: 5);

  /// Maximum concurrent downloads allowed
  static const int maxConcurrentDownloads = 8;

  /// Check if we're currently rate limited
  bool get isRateLimited {
    if (_rateLimitedUntil == null) return false;
    if (DateTime.now().isAfter(_rateLimitedUntil!)) {
      _rateLimitedUntil = null;
      return false;
    }
    return true;
  }

  /// Get seconds remaining until rate limit expires
  int get secondsRemaining {
    if (_rateLimitedUntil == null) return 0;
    final remaining = _rateLimitedUntil!.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// Check if we can make a delivery API request
  bool get canMakeRequest {
    if (isRateLimited) return false;

    // Clean up old requests
    _cleanupOldRequests();

    // Check if we've hit the limit
    return _recentRequests.length < maxRequestsPerWindow;
  }

  /// Get seconds until we can make another request (if at limit)
  int get secondsUntilNextRequest {
    if (isRateLimited) return secondsRemaining;

    _cleanupOldRequests();

    if (_recentRequests.length >= maxRequestsPerWindow) {
      // Find when the oldest request will expire
      final oldest = _recentRequests.first;
      final expiresAt = oldest.add(rateLimitWindow);
      final remaining = expiresAt.difference(DateTime.now()).inSeconds;
      return remaining > 0 ? remaining : 0;
    }

    return 0;
  }

  /// Record a delivery API request
  void recordRequest() {
    _cleanupOldRequests();
    _recentRequests.add(DateTime.now());
    _emitState();
  }

  /// Set rate limited state from 429 response
  void setRateLimited(int retryAfterSeconds) {
    _rateLimitedUntil =
        DateTime.now().add(Duration(seconds: retryAfterSeconds));
    _emitState();

    // Start countdown timer
    _startCountdownTimer();
  }

  /// Parse retry-after from response headers or body
  int parseRetryAfter(Map<String, String> headers, String? body) {
    // Try retry-after header first
    if (headers.containsKey('retry-after')) {
      final value = headers['retry-after'];
      if (value != null) {
        final seconds = int.tryParse(value);
        if (seconds != null) return seconds;
      }
    }

    // Default to 5 minutes if not specified
    return 300;
  }

  /// Clear rate limit (e.g., after successful request)
  void clearRateLimit() {
    _rateLimitedUntil = null;
    _emitState();
  }

  /// Get current state for UI
  RateLimitState get currentState {
    _cleanupOldRequests();
    return RateLimitState(
      isRateLimited: isRateLimited,
      secondsRemaining: secondsRemaining,
      recentRequestCount: _recentRequests.length,
      maxRequestsPerWindow: maxRequestsPerWindow,
      canMakeRequest: canMakeRequest,
      secondsUntilNextRequest: secondsUntilNextRequest,
    );
  }

  void _cleanupOldRequests() {
    final cutoff = DateTime.now().subtract(rateLimitWindow);
    _recentRequests.removeWhere((time) => time.isBefore(cutoff));
  }

  void _emitState() {
    _stateController.add(currentState);
  }

  Timer? _countdownTimer;

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isRateLimited) {
        _countdownTimer?.cancel();
        _countdownTimer = null;
      }
      _emitState();
    });
  }

  void dispose() {
    _countdownTimer?.cancel();
    _stateController.close();
  }
}

/// State of rate limiting for UI
class RateLimitState {
  final bool isRateLimited;
  final int secondsRemaining;
  final int recentRequestCount;
  final int maxRequestsPerWindow;
  final bool canMakeRequest;
  final int secondsUntilNextRequest;

  const RateLimitState({
    required this.isRateLimited,
    required this.secondsRemaining,
    required this.recentRequestCount,
    required this.maxRequestsPerWindow,
    required this.canMakeRequest,
    required this.secondsUntilNextRequest,
  });

  String get formattedTimeRemaining {
    if (secondsRemaining <= 0) return '';
    final minutes = secondsRemaining ~/ 60;
    final seconds = secondsRemaining % 60;
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }
}

/// Global instance
final fpRateLimitManager = FPRateLimitManager();
