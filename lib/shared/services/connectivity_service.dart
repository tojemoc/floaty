import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Connectivity status enum
enum ConnectivityStatus {
  connected,
  disconnected,
  checking,
}

/// Service to monitor network connectivity
/// Designed to work gracefully with offline downloads feature
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final _statusController = StreamController<ConnectivityStatus>.broadcast();
  Stream<ConnectivityStatus> get statusStream => _statusController.stream;

  ConnectivityStatus _currentStatus = ConnectivityStatus.checking;
  ConnectivityStatus get currentStatus => _currentStatus;

  Timer? _periodicCheck;
  DateTime? _lastCheck;

  /// Minimum interval between connectivity checks (to be respectful to servers)
  static const Duration _minCheckInterval = Duration(seconds: 30);

  /// Initialize the connectivity service
  void initialize() {
    _startPeriodicCheck();
  }

  /// Start periodic connectivity checks
  void _startPeriodicCheck() {
    _periodicCheck?.cancel();
    _periodicCheck = Timer.periodic(const Duration(minutes: 1), (_) {
      checkConnectivity();
    });
    // Initial check
    checkConnectivity();
  }

  /// Check if we have internet connectivity
  /// Returns true if connected, false otherwise
  Future<bool> checkConnectivity({bool force = false}) async {
    // Respect rate limiting unless forced
    if (!force && _lastCheck != null) {
      final timeSinceLastCheck = DateTime.now().difference(_lastCheck!);
      if (timeSinceLastCheck < _minCheckInterval) {
        return _currentStatus == ConnectivityStatus.connected;
      }
    }

    _lastCheck = DateTime.now();
    _currentStatus = ConnectivityStatus.checking;

    if (kIsWeb) {
      // On web, we can't do socket checks, so try a simple HTTP request
      return await _checkWithHttp();
    }

    try {
      // Try to lookup a common DNS (Google's DNS)
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));

      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        _updateStatus(ConnectivityStatus.connected);
        return true;
      }
    } on SocketException catch (_) {
      _updateStatus(ConnectivityStatus.disconnected);
      return false;
    } on TimeoutException catch (_) {
      _updateStatus(ConnectivityStatus.disconnected);
      return false;
    } catch (e) {
      // Fallback to HTTP check
      return await _checkWithHttp();
    }

    _updateStatus(ConnectivityStatus.disconnected);
    return false;
  }

  /// Fallback HTTP-based connectivity check
  Future<bool> _checkWithHttp() async {
    try {
      final response = await http
          .head(Uri.parse('https://www.google.com'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        _updateStatus(ConnectivityStatus.connected);
        return true;
      }
    } catch (_) {
      // Ignore - we'll mark as disconnected
    }

    _updateStatus(ConnectivityStatus.disconnected);
    return false;
  }

  /// Update status and notify listeners
  void _updateStatus(ConnectivityStatus status) {
    if (_currentStatus != status) {
      _currentStatus = status;
      _statusController.add(status);
    }
  }

  /// Check if currently connected (synchronous, uses cached status)
  bool get isConnected => _currentStatus == ConnectivityStatus.connected;

  /// Check if currently disconnected
  bool get isDisconnected => _currentStatus == ConnectivityStatus.disconnected;

  /// Dispose resources
  void dispose() {
    _periodicCheck?.cancel();
    _statusController.close();
  }
}

/// Global connectivity service instance
final connectivityService = ConnectivityService();

/// Riverpod provider for connectivity status
final connectivityStatusProvider =
    StreamProvider<ConnectivityStatus>((ref) async* {
  // Initialize service
  connectivityService.initialize();

  // Yield initial status
  yield connectivityService.currentStatus;

  // Listen to status changes
  await for (final status in connectivityService.statusStream) {
    yield status;
  }
});

/// Simple provider to check if connected (for convenience)
final isConnectedProvider = Provider<bool>((ref) {
  final status = ref.watch(connectivityStatusProvider);
  return status.maybeWhen(
    data: (s) => s == ConnectivityStatus.connected,
    orElse: () => true, // Assume connected by default to avoid blocking
  );
});
