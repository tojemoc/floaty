import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:floaty/shared/utils/exceptions.dart';
import 'package:http/http.dart' as http;

/// A wrapper class that represents the result of an API operation
/// Can be either a success with data or a failure with an error
class ApiResult<T> {
  final T? data;
  final FloatyException? error;
  final bool isSuccess;

  const ApiResult._({this.data, this.error, required this.isSuccess});

  /// Creates a successful result with data
  factory ApiResult.success(T data) {
    return ApiResult._(data: data, isSuccess: true);
  }

  /// Creates a failed result with an error
  factory ApiResult.failure(FloatyException error) {
    return ApiResult._(error: error, isSuccess: false);
  }

  /// Returns true if this is a failure
  bool get isFailure => !isSuccess;

  /// Maps the data to a new type if successful
  ApiResult<R> map<R>(R Function(T data) transform) {
    if (isSuccess && data != null) {
      return ApiResult.success(transform(data as T));
    }
    return ApiResult.failure(error ?? const UnexpectedException());
  }

  /// Executes one of two functions based on success/failure
  R fold<R>({
    required R Function(T data) onSuccess,
    required R Function(FloatyException error) onFailure,
  }) {
    if (isSuccess && data != null) {
      return onSuccess(data as T);
    }
    return onFailure(error ?? const UnexpectedException());
  }

  /// Returns data or throws the error
  T getOrThrow() {
    if (isSuccess && data != null) {
      return data as T;
    }
    throw error ?? const UnexpectedException();
  }

  /// Returns data or a default value
  T getOrDefault(T defaultValue) {
    if (isSuccess && data != null) {
      return data as T;
    }
    return defaultValue;
  }

  /// Returns data or null
  T? getOrNull() => isSuccess ? data : null;
}

/// Helper class for executing API calls with proper error handling
class ApiErrorHandler {
  static final Logger _log = Logger('ApiErrorHandler');

  /// Wraps an async operation with comprehensive error handling
  /// Converts various error types to appropriate FloatyException types
  static Future<ApiResult<T>> execute<T>(Future<T> Function() operation) async {
    try {
      final result = await operation();
      return ApiResult.success(result);
    } on SocketException catch (e) {
      return ApiResult.failure(
        NoInternetException(
          details: e.message,
          originalError: e,
        ),
      );
    } on TimeoutException catch (e) {
      return ApiResult.failure(
        TimeoutException(
          details: e.message,
          originalError: e,
        ) as FloatyException,
      );
    } on http.ClientException catch (e) {
      return ApiResult.failure(
        NoInternetException(
          details: e.message,
          originalError: e,
        ),
      );
    } on FormatException catch (e) {
      return ApiResult.failure(
        ParseException(
          details: e.message,
          originalError: e,
        ),
      );
    } on FloatyException catch (e) {
      return ApiResult.failure(e);
    } catch (e, stackTrace) {
      // Log unexpected errors for debugging
      _log.severe('Unexpected error: $e', e, stackTrace);
      return ApiResult.failure(
        UnexpectedException(
          details: e.toString(),
          originalError: e,
        ),
      );
    }
  }

  /// Parses HTTP status codes and returns appropriate exceptions
  static FloatyException? getExceptionFromStatusCode(
    int statusCode, {
    String? responseBody,
  }) {
    if (statusCode >= 200 && statusCode < 300) {
      return null; // Success
    }

    switch (statusCode) {
      case 401:
        return AuthException(
          message: 'Unauthorized',
          details: responseBody,
        );
      case 403:
        return const ServerException(
          message: 'Forbidden',
          statusCode: 403,
        );
      case 404:
        return const ContentUnavailableException(
          message: 'Not found',
        );
      case 429:
        return const ServerException(
          message: 'Rate limited',
          statusCode: 429,
        );
      default:
        if (statusCode >= 500) {
          return ServerException(
            message: 'Server error',
            statusCode: statusCode,
            details: responseBody,
          );
        }
        return ServerException(
          message: 'Request failed',
          statusCode: statusCode,
          details: responseBody,
        );
    }
  }

  /// Checks if an error is a connectivity-related error
  static bool isConnectivityError(dynamic error) {
    return error is NoInternetException ||
        error is TimeoutException ||
        error is SocketException ||
        error is http.ClientException ||
        (error is FloatyException && error.originalError is SocketException) ||
        (error is FloatyException &&
            error.originalError is http.ClientException);
  }
}

/// Extension to add error handling to http.Response
extension HttpResponseExtension on http.Response {
  /// Checks if the response was successful
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// Gets a FloatyException if the response was not successful
  FloatyException? get exception {
    if (isSuccess) return null;
    return ApiErrorHandler.getExceptionFromStatusCode(statusCode,
        responseBody: body);
  }

  /// Throws an exception if the response was not successful
  void throwIfError() {
    final e = exception;
    if (e != null) throw e;
  }
}
