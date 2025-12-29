// Custom exceptions for the Floaty app
// Provides specific error types for better error handling and user feedback

/// Base exception for all Floaty-related errors
abstract class FloatyException implements Exception {
  final String message;
  final String? details;
  final dynamic originalError;

  const FloatyException(this.message, {this.details, this.originalError});

  @override
  String toString() => message;

  /// Returns user-friendly message for display
  String get userMessage => message;

  /// Returns the appropriate error image asset
  String get errorImage => 'assets/error.png';
}

/// Exception thrown when there's no internet connection
class NoInternetException extends FloatyException {
  const NoInternetException({String? details, dynamic originalError})
      : super(
          'No internet connection',
          details: details,
          originalError: originalError,
        );

  @override
  String get userMessage => 'No internet connection';

  @override
  String get errorImage => 'assets/nointernet.png';
}

/// Exception thrown when a network request times out
class TimeoutException extends FloatyException {
  const TimeoutException({String? details, dynamic originalError})
      : super(
          'Request timed out',
          details: details,
          originalError: originalError,
        );

  @override
  String get userMessage => 'The request took too long. Please try again.';

  @override
  String get errorImage => 'assets/nointernet.png';
}

/// Exception thrown when the server returns an error
class ServerException extends FloatyException {
  final int? statusCode;

  const ServerException({
    String message = 'Server error',
    this.statusCode,
    String? details,
    dynamic originalError,
  }) : super(message, details: details, originalError: originalError);

  @override
  String get userMessage {
    if (statusCode == 401) {
      return 'Your session has expired. Please log in again.';
    } else if (statusCode == 403) {
      return 'You don\'t have permission to access this content.';
    } else if (statusCode == 404) {
      return 'The requested content was not found.';
    } else if (statusCode == 429) {
      return 'Too many requests. Please wait a moment.';
    } else if (statusCode != null && statusCode! >= 500) {
      return 'Server is having issues. Please try again later.';
    }
    return message;
  }

  @override
  String get errorImage => 'assets/error.png';
}

/// Exception thrown when there's an authentication error
class AuthException extends FloatyException {
  const AuthException({
    String message = 'Authentication failed',
    String? details,
    dynamic originalError,
  }) : super(message, details: details, originalError: originalError);

  @override
  String get userMessage => 'Please log in to continue.';

  @override
  String get errorImage => 'assets/error.png';
}

/// Exception thrown for unexpected errors
class UnexpectedException extends FloatyException {
  const UnexpectedException({
    String message = 'An unexpected error occurred',
    String? details,
    dynamic originalError,
  }) : super(message, details: details, originalError: originalError);

  @override
  String get userMessage => 'Something went wrong. Please try again.';

  @override
  String get errorImage => 'assets/unexpected.png';
}

/// Exception thrown when data parsing fails
class ParseException extends FloatyException {
  const ParseException({
    String message = 'Failed to parse data',
    String? details,
    dynamic originalError,
  }) : super(message, details: details, originalError: originalError);

  @override
  String get userMessage => 'Failed to load content properly.';

  @override
  String get errorImage => 'assets/error.png';
}

/// Exception thrown when content is not available
class ContentUnavailableException extends FloatyException {
  const ContentUnavailableException({
    String message = 'Content unavailable',
    String? details,
    dynamic originalError,
  }) : super(message, details: details, originalError: originalError);

  @override
  String get userMessage => 'This content is currently unavailable.';

  @override
  String get errorImage => 'assets/error.png';
}
