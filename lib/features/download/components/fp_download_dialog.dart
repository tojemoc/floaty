import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:floaty/features/api/models/definitions.dart';
import 'package:floaty/features/download/repositories/fp_download_provider.dart';
import 'package:floaty/features/download/controllers/fp_download_service.dart';

/// Dialog for selecting download quality
class FPDownloadDialog extends ConsumerStatefulWidget {
  final ContentPostV3Response post;
  final dynamic attachment; // VideoAttachmentModel or AudioAttachmentModel
  final String? creatorName;
  final String? channelName;

  const FPDownloadDialog({
    super.key,
    required this.post,
    required this.attachment,
    this.creatorName,
    this.channelName,
  });

  @override
  ConsumerState<FPDownloadDialog> createState() => _FPDownloadDialogState();

  /// Show the download dialog
  static Future<void> show(
    BuildContext context, {
    required ContentPostV3Response post,
    required dynamic attachment,
    String? creatorName,
    String? channelName,
  }) async {
    return showDialog(
      context: context,
      builder: (context) => FPDownloadDialog(
        post: post,
        attachment: attachment,
        creatorName: creatorName,
        channelName: channelName,
      ),
    );
  }
}

class _FPDownloadDialogState extends ConsumerState<FPDownloadDialog> {
  @override
  void initState() {
    super.initState();
    // Fetch download options when dialog opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final attachmentId = _getAttachmentId();
      final attachmentTitle = _getAttachmentTitle();
      if (attachmentId != null) {
        ref
            .read(fpDownloadOptionsProvider.notifier)
            .fetchDownloadOptions(attachmentId, attachmentTitle);
      }
    });
  }

  String? _getAttachmentId() {
    if (widget.attachment is VideoAttachmentModel) {
      return (widget.attachment as VideoAttachmentModel).id;
    } else if (widget.attachment is AudioAttachmentModel) {
      return (widget.attachment as AudioAttachmentModel).id;
    }
    return null;
  }

  String _getAttachmentTitle() {
    if (widget.attachment is VideoAttachmentModel) {
      return (widget.attachment as VideoAttachmentModel).title;
    } else if (widget.attachment is AudioAttachmentModel) {
      return (widget.attachment as AudioAttachmentModel).title;
    }
    return 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fpDownloadOptionsProvider);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.download),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Download',
              style: theme.textTheme.titleLarge,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              _getAttachmentTitle(),
              style: theme.textTheme.titleSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),

            // Content based on state
            if (state.isLoading)
              const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.error != null)
              _buildErrorState(state, theme)
            else if (state.options.isEmpty)
              const SizedBox(
                height: 100,
                child: Center(child: Text('No download options available')),
              )
            else
              _buildOptionsList(state, theme),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            ref.read(fpDownloadOptionsProvider.notifier).reset();
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildErrorState(FPDownloadOptionsState state, ThemeData theme) {
    return SizedBox(
      height: 120,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              state.isRateLimited ? Icons.schedule : Icons.error_outline,
              color: state.isRateLimited ? Colors.orange : Colors.red,
              size: 32,
            ),
            const SizedBox(height: 8),
            if (state.isRateLimited) ...[
              Text(
                'Downloads Rate Limited',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                state.rateLimitSecondsRemaining > 0
                    ? 'Please wait ${state.formattedTimeRemaining}'
                    : 'Please try again...',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              if (state.rateLimitSecondsRemaining > 0)
                LinearProgressIndicator(
                  value: 1 -
                      (state.rateLimitSecondsRemaining /
                          300), // Assume 5 min max
                  backgroundColor: Colors.orange.withValues(alpha: 0.2),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.orange),
                ),
            ] else ...[
              Text(
                state.error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (state.isRateLimited &&
                state.rateLimitSecondsRemaining <= 0) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: () {
                  final attachmentId = _getAttachmentId();
                  final attachmentTitle = _getAttachmentTitle();
                  if (attachmentId != null) {
                    ref
                        .read(fpDownloadOptionsProvider.notifier)
                        .fetchDownloadOptions(attachmentId, attachmentTitle);
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOptionsList(FPDownloadOptionsState state, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Destination selector
        Text(
          'Save to:',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 4),
        SegmentedButton<FPDownloadDestination>(
          segments: const [
            ButtonSegment(
              value: FPDownloadDestination.offline,
              label: Text('Offline Library'),
              icon: Icon(Icons.library_music),
            ),
            ButtonSegment(
              value: FPDownloadDestination.external,
              label: Text('Downloads'),
              icon: Icon(Icons.folder),
            ),
          ],
          selected: {state.selectedDestination},
          onSelectionChanged: (selection) {
            ref
                .read(fpDownloadOptionsProvider.notifier)
                .setDestination(selection.first);
          },
        ),
        const SizedBox(height: 16),
        Text(
          'Select Quality:',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 250),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: state.options.length,
            itemBuilder: (context, index) {
              final option = state.options[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.high_quality),
                title: Text(option.qualityLabel),
                subtitle:
                    option.fileSize != null ? Text(option.fileSize!) : null,
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _startDownload(option, state.selectedDestination),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _startDownload(
    FPDownloadOption option,
    FPDownloadDestination destination,
  ) async {
    if (!mounted) return;

    Navigator.of(context).pop();

    final success =
        await ref.read(fpDownloadOptionsProvider.notifier).startDownload(
              post: widget.post,
              attachment: widget.attachment,
              option: option,
              creatorName: widget.creatorName,
              channelName: widget.channelName,
              destination: destination,
            );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Download started: ${option.qualityLabel}'
              : 'Failed to start download',
        ),
        action: success
            ? SnackBarAction(
                label: 'View',
                onPressed: () {
                  context.push('/downloads');
                },
              )
            : null,
      ),
    );

    ref.read(fpDownloadOptionsProvider.notifier).reset();
  }
}

/// Button to trigger download dialog
class FPDownloadButton extends ConsumerWidget {
  final ContentPostV3Response post;
  final dynamic attachment;
  final String? creatorName;
  final String? channelName;
  final bool showLabel;

  const FPDownloadButton({
    super.key,
    required this.post,
    required this.attachment,
    this.creatorName,
    this.channelName,
    this.showLabel = false,
  });

  String? _getAttachmentId() {
    if (attachment is VideoAttachmentModel) {
      return (attachment as VideoAttachmentModel).id;
    } else if (attachment is AudioAttachmentModel) {
      return (attachment as AudioAttachmentModel).id;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachmentId = _getAttachmentId();
    final isOffline = attachmentId != null
        ? fpDownloadService.isAvailableOffline(attachmentId)
        : false;

    if (showLabel) {
      return TextButton.icon(
        icon: Icon(
          isOffline ? Icons.download_done : Icons.download,
          color: isOffline ? Colors.green : null,
        ),
        label: Text(isOffline ? 'Downloaded' : 'Download'),
        onPressed: isOffline
            ? null
            : () => FPDownloadDialog.show(
                  context,
                  post: post,
                  attachment: attachment,
                  creatorName: creatorName,
                  channelName: channelName,
                ),
      );
    }

    return IconButton(
      icon: Icon(
        isOffline ? Icons.download_done : Icons.download,
        color: isOffline ? Colors.green : null,
      ),
      tooltip: isOffline ? 'Downloaded' : 'Download for offline',
      onPressed: isOffline
          ? null
          : () => FPDownloadDialog.show(
                context,
                post: post,
                attachment: attachment,
                creatorName: creatorName,
                channelName: channelName,
              ),
    );
  }
}
