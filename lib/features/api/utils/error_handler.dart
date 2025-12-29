import 'dart:async';
import 'dart:io';
import 'package:floaty/shared/utils/exceptions.dart';
import 'package:http/http.dart' as http;

/// Helper class for handling errors in API calls
/// Works alongside the existing fpapi.dart without requiring major changes
class FPApiErrorHandler {
  /// Wraps a response body and converts error strings to exceptions
  static FloatyException? parseErrorResponse(dynamic response) {
    if (response == null) {
      return const UnexpectedException(message: 'No response received');
    }

    if (response is String) {
      if (response.startsWith('Error:')) {
        final errorMessage = response.substring(6).trim();
        return _parseErrorMessage(errorMessage);
      }
      if (response.contains('StatusCode: 429')) {
        return const ServerException(
          message: 'Rate limit exceeded',
          statusCode: 429,
        );
      }
      if (response.contains('StatusCode: 401')) {
        return const AuthException(message: 'Unauthorized');
      }
      if (response.contains('StatusCode: 403')) {
        return const ServerException(
          message: 'Forbidden',
          statusCode: 403,
        );
      }
      if (response.contains('StatusCode: 404')) {
        return const ContentUnavailableException(message: 'Not found');
      }
      if (response.contains('StatusCode: 5')) {
        return const ServerException(
          message: 'Server error',
          statusCode: 500,
        );
      }
    }

    if (response is Map && response.containsKey('statusCode')) {
      final statusCode = response['statusCode'] as int?;
      final body = response['body'] as String?;
      if (statusCode != null && statusCode >= 400) {
        return _exceptionFromStatusCode(statusCode, body);
      }
    }

    return null;
  }

  /// Parse error message string to determine exception type
  static FloatyException _parseErrorMessage(String message) {
    final lowerMessage = message.toLowerCase();

    if (lowerMessage.contains('socketexception') ||
        lowerMessage.contains('failed host lookup') ||
        lowerMessage.contains('network is unreachable') ||
        lowerMessage.contains('no address associated') ||
        lowerMessage.contains('connection refused')) {
      return NoInternetException(details: message);
    }

    if (lowerMessage.contains('timeout') ||
        lowerMessage.contains('timed out')) {
      return TimeoutException(details: message);
    }

    if (lowerMessage.contains('handshake') ||
        lowerMessage.contains('certificate')) {
      return const ServerException(
        message: 'SSL/TLS error',
        details: 'There was a problem with the secure connection',
      );
    }

    if (lowerMessage.contains('formatexception') ||
        lowerMessage.contains('unexpected character')) {
      return ParseException(details: message);
    }

    return UnexpectedException(details: message);
  }

  /// Create exception from HTTP status code
  static FloatyException _exceptionFromStatusCode(int code, String? body) {
    switch (code) {
      case 401:
        return AuthException(details: body);
      case 403:
        return ServerException(
          message: 'Forbidden',
          statusCode: 403,
          details: body,
        );
      case 404:
        return ContentUnavailableException(details: body);
      case 429:
        return ServerException(
          message: 'Rate limit exceeded',
          statusCode: 429,
          details: body,
        );
      default:
        if (code >= 500) {
          return ServerException(
            message: 'Server error',
            statusCode: code,
            details: body,
          );
        }
        return ServerException(
          message: 'Request failed',
          statusCode: code,
          details: body,
        );
    }
  }

  /// Check if an error is recoverable (can retry)
  static bool isRecoverable(FloatyException exception) {
    return exception is NoInternetException ||
        exception is TimeoutException ||
        (exception is ServerException && exception.statusCode == 429) ||
        (exception is ServerException && (exception.statusCode ?? 0) >= 500);
  }

  /// Check if error is a connectivity issue
  static bool isConnectivityError(dynamic error) {
    if (error is NoInternetException || error is TimeoutException) {
      return true;
    }
    if (error is SocketException || error is http.ClientException) {
      return true;
    }
    if (error is FloatyException) {
      return error.originalError is SocketException ||
          error.originalError is http.ClientException;
    }
    if (error is String) {
      final lower = error.toLowerCase();
      return lower.contains('socketexception') ||
          lower.contains('failed host lookup') ||
          lower.contains('network is unreachable') ||
          lower.contains('no address') ||
          lower.contains('timeout');
    }
    return false;
  }

  /// Wrap an async operation with timeout and error handling
  static Future<T> withErrorHandling<T>(
    Future<T> Function() operation, {
    Duration timeout = const Duration(seconds: 30),
    T Function()? onError,
  }) async {
    try {
      return await operation().timeout(timeout);
    } on TimeoutException catch (e) {
      if (onError != null) return onError();
      throw TimeoutException(originalError: e) as FloatyException;
    } on SocketException catch (e) {
      if (onError != null) return onError();
      throw NoInternetException(details: e.message, originalError: e);
    } on http.ClientException catch (e) {
      if (onError != null) return onError();
      throw NoInternetException(details: e.message, originalError: e);
    } on FloatyException {
      rethrow;
    } catch (e) {
      if (onError != null) return onError();
      throw UnexpectedException(details: e.toString(), originalError: e);
    }
  }
}

/// Extension on Stream to add error handling
extension StreamErrorHandling<T> on Stream<T> {
  /// Maps errors in the stream to FloatyException
  Stream<T> handleErrors({T Function(FloatyException)? onError}) {
    return handleError((error, stackTrace) {
      final exception = _toFloatyException(error);
      if (onError != null) {
        return onError(exception);
      }
      throw exception;
    });
  }

  FloatyException _toFloatyException(dynamic error) {
    if (error is FloatyException) return error;
    if (error is SocketException) {
      return NoInternetException(details: error.message, originalError: error);
    }
    if (error is http.ClientException) {
      return NoInternetException(details: error.message, originalError: error);
    }
    if (error is TimeoutException) {
      return TimeoutException(originalError: error) as FloatyException;
    }
    return UnexpectedException(details: error.toString(), originalError: error);
  }
}
