import 'package:floaty/shared/utils/exceptions.dart';
import 'package:flutter/material.dart';

/// Error types for displaying appropriate error screens
enum ErrorType {
  general,
  noConnection,
  timeout,
  serverError,
  notFound,
  unauthorized,
  unexpected,
}

/// A comprehensive error screen widget that displays errors
/// with appropriate images, messages, and optional retry functionality
class ErrorScreen extends StatefulWidget {
  final String? message;
  final String? subtext;
  final String? image;
  final VoidCallback? onRetry;
  final ErrorType errorType;
  final bool compact;
  final FloatyException? exception;

  const ErrorScreen({
    super.key,
    this.message,
    this.subtext,
    this.image,
    this.onRetry,
    this.errorType = ErrorType.general,
    this.compact = false,
    this.exception,
  });

  /// Creates an ErrorScreen from a FloatyException
  factory ErrorScreen.fromException(
    FloatyException exception, {
    VoidCallback? onRetry,
    bool compact = false,
    Key? key,
  }) {
    ErrorType type = ErrorType.general;
    if (exception is NoInternetException) {
      type = ErrorType.noConnection;
    } else if (exception is TimeoutException) {
      type = ErrorType.timeout;
    } else if (exception is ServerException) {
      type = exception.statusCode == 404
          ? ErrorType.notFound
          : ErrorType.serverError;
    } else if (exception is AuthException) {
      type = ErrorType.unauthorized;
    } else if (exception is UnexpectedException) {
      type = ErrorType.unexpected;
    }

    return ErrorScreen(
      key: key,
      message: exception.details,
      subtext: exception.userMessage,
      image: exception.errorImage,
      onRetry: onRetry,
      errorType: type,
      compact: compact,
      exception: exception,
    );
  }

  /// Creates a no connection error screen
  factory ErrorScreen.noConnection({
    VoidCallback? onRetry,
    bool compact = false,
    Key? key,
  }) {
    return ErrorScreen(
      key: key,
      image: 'assets/nointernet.png',
      subtext: 'No internet connection',
      onRetry: onRetry,
      errorType: ErrorType.noConnection,
      compact: compact,
    );
  }

  /// Creates a timeout error screen
  factory ErrorScreen.timeout({
    VoidCallback? onRetry,
    bool compact = false,
    Key? key,
  }) {
    return ErrorScreen(
      key: key,
      image: 'assets/nointernet.png',
      subtext: 'The request took too long',
      onRetry: onRetry,
      errorType: ErrorType.timeout,
      compact: compact,
    );
  }

  /// Creates a server error screen
  factory ErrorScreen.serverError({
    String? message,
    VoidCallback? onRetry,
    bool compact = false,
    Key? key,
  }) {
    return ErrorScreen(
      key: key,
      image: 'assets/error.png',
      subtext: 'Server is having issues',
      message: message,
      onRetry: onRetry,
      errorType: ErrorType.serverError,
      compact: compact,
    );
  }

  @override
  State<ErrorScreen> createState() => _ErrorScreenState();
}

class _ErrorScreenState extends State<ErrorScreen>
    with SingleTickerProviderStateMixin {
  bool revealed = false;
  bool _isRetrying = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  String _getTitle() {
    switch (widget.errorType) {
      case ErrorType.noConnection:
        return 'You\'re offline';
      case ErrorType.timeout:
        return 'Connection timed out';
      case ErrorType.serverError:
        return 'Server hiccup';
      case ErrorType.notFound:
        return 'Not found';
      case ErrorType.unauthorized:
        return 'Access denied';
      case ErrorType.unexpected:
        return 'Oops!';
      case ErrorType.general:
        return 'Well this is embarrassing';
    }
  }

  String _getImage() {
    if (widget.image != null) return widget.image!;
    switch (widget.errorType) {
      case ErrorType.noConnection:
      case ErrorType.timeout:
        return 'assets/nointernet.png';
      case ErrorType.unexpected:
        return 'assets/unexpected.png';
      case ErrorType.serverError:
      case ErrorType.notFound:
      case ErrorType.unauthorized:
      case ErrorType.general:
        return 'assets/error.png';
    }
  }

  Future<void> _handleRetry() async {
    if (_isRetrying || widget.onRetry == null) return;

    setState(() => _isRetrying = true);

    // Small delay to show loading state
    await Future.delayed(const Duration(milliseconds: 300));

    widget.onRetry!();

    // Reset retrying state after a short delay
    // The parent widget should handle the actual state change
    if (mounted) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => _isRetrying = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (widget.compact) {
      return _buildCompactView(theme, colorScheme);
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Error image
              Image(
                image: AssetImage(_getImage()),
                width: 180,
                height: 180,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    _getIconForErrorType(),
                    size: 120,
                    color: colorScheme.error.withValues(alpha: 0.7),
                  );
                },
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                _getTitle(),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // Subtext/message
              Text(
                widget.subtext ?? 'An error has occurred.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),

              // Technical details (expandable)
              if (widget.message != null && widget.message!.isNotEmpty) ...[
                const SizedBox(height: 16),
                if (!revealed)
                  TextButton.icon(
                    onPressed: () => setState(() => revealed = true),
                    icon: const Icon(Icons.expand_more, size: 20),
                    label: const Text('Show details'),
                  )
                else
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.expand_less, size: 20),
                              onPressed: () => setState(() => revealed = false),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                        SelectableText(
                          widget.message!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],

              // Retry button
              if (widget.onRetry != null) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isRetrying ? null : _handleRetry,
                  icon: _isRetrying
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(_isRetrying ? 'Retrying...' : 'Try again'),
                ),
              ],

              // Hint for offline mode
              if (widget.errorType == ErrorType.noConnection) ...[
                const SizedBox(height: 16),
                Text(
                  'Downloaded content is still available offline.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactView(ThemeData theme, ColorScheme colorScheme) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _getIconForErrorType(),
              size: 32,
              color: colorScheme.error.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getTitle(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    widget.subtext ?? 'An error has occurred.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.onRetry != null)
              IconButton(
                onPressed: _isRetrying ? null : _handleRetry,
                icon: _isRetrying
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      )
                    : Icon(Icons.refresh, color: colorScheme.primary),
              ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForErrorType() {
    switch (widget.errorType) {
      case ErrorType.noConnection:
        return Icons.wifi_off_rounded;
      case ErrorType.timeout:
        return Icons.timer_off_rounded;
      case ErrorType.serverError:
        return Icons.cloud_off_rounded;
      case ErrorType.notFound:
        return Icons.search_off_rounded;
      case ErrorType.unauthorized:
        return Icons.lock_outline_rounded;
      case ErrorType.unexpected:
        return Icons.error_outline_rounded;
      case ErrorType.general:
        return Icons.warning_amber_rounded;
    }
  }
}

/// A widget that displays a small inline error indicator
/// Useful for showing errors within cards or list items
class InlineErrorIndicator extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;
  final bool showRetry;

  const InlineErrorIndicator({
    super.key,
    this.message,
    this.onRetry,
    this.showRetry = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: colorScheme.error,
          ),
          if (message != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message!,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onErrorContainer,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (showRetry && onRetry != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onRetry,
              child: Icon(
                Icons.refresh,
                size: 16,
                color: colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A banner that appears at the top of the screen when offline
class OfflineBanner extends StatelessWidget {
  final VoidCallback? onDismiss;

  const OfflineBanner({super.key, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: 20,
                color: colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'You\'re offline. Some features may not be available.',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: colorScheme.onErrorContainer,
                  ),
                  onPressed: onDismiss,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
