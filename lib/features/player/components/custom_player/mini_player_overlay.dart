import 'package:better_player_plus/better_player_plus.dart';
import 'package:floaty/features/player/controllers/media_player_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:text_scroll/text_scroll.dart';

/// Provider for play state used by mini player
final miniPlayerPlayingStateProvider = StreamProvider.autoDispose<bool>((ref) {
  final mediaService = ref.watch(mediaPlayerServiceProvider.notifier);
  return mediaService.playingStream;
});

/// A mini player overlay widget that appears at the bottom of the screen.
/// This is displayed as an overlay via the root layout when MediaPlayerState.mini is active.
class MiniPlayerOverlay extends ConsumerWidget {
  const MiniPlayerOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mediaService = ref.read(mediaPlayerServiceProvider.notifier);
    final isPlaying = ref.watch(miniPlayerPlayingStateProvider);

    final title = mediaService.currentTitle ?? '';
    final artist = mediaService.currentArtist ?? '';
    final thumbnailUrl = mediaService.currentThumbnailUrl;
    final videoController = mediaService.videoController;

    return Material(
      elevation: 8,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _expandToMain(context, ref),
        child: Container(
          height: 72,
          color: theme.cardColor,
          child: Row(
            children: [
              // Video/Thumbnail preview
              _buildPreview(videoController, null, thumbnailUrl),
              // Title and controls
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextScroll(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        fadedBorder: true,
                        fadedBorderWidth: 0.1,
                        pauseBetween: const Duration(seconds: 5),
                        intervalSpaces: 6,
                        velocity:
                            const Velocity(pixelsPerSecond: Offset(20, 0)),
                      ),
                      AutoSizeText(
                        artist,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodySmall?.color,
                        ),
                        minFontSize: 6,
                        maxFontSize: 16,
                        textScaleFactor: 0.85,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // Playback controls
                      Row(
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            child: const Icon(Icons.fast_rewind, size: 18),
                            onTap: () => _seekBackward(mediaService),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              child: Icon(
                                isPlaying.when(
                                  data: (playing) =>
                                      playing ? Icons.pause : Icons.play_arrow,
                                  loading: () => Icons.pause,
                                  error: (_, __) => Icons.pause,
                                ),
                                size: 18,
                              ),
                              onTap: () => mediaService.playpause(),
                            ),
                          ),
                          InkWell(
                            child: const Icon(Icons.fast_forward, size: 18),
                            onTap: () => _seekForward(mediaService),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Close button
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  child: const Icon(Icons.close, size: 16),
                  onTap: () => _closePlayer(mediaService),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(
    VideoController? videoController,
    BetterPlayerController? betterPlayerController,
    String? thumbnailUrl,
  ) {
    if (videoController != null) {
      // MediaKit player
      return SizedBox(
        width: 128,
        height: 72,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Video(
            controller: videoController,
            controls: NoVideoControls,
            fit: BoxFit.cover,
          ),
        ),
      );
    } else if (betterPlayerController != null) {
      // BetterPlayer
      return SizedBox(
        width: 128,
        height: 72,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: BetterPlayer(controller: betterPlayerController),
        ),
      );
    } else if (thumbnailUrl != null) {
      return Image.network(
        thumbnailUrl,
        width: 128,
        height: 72,
        fit: BoxFit.cover,
      );
    } else {
      return Container(
        width: 128,
        height: 72,
        color: Colors.grey[800],
        child: const Icon(Icons.music_note, size: 32),
      );
    }
  }

  void _seekBackward(MediaPlayerService mediaService) {
    mediaService.seek(
      mediaService.currentPosition - const Duration(seconds: 10),
    );
  }

  void _seekForward(MediaPlayerService mediaService) {
    mediaService.seek(
      mediaService.currentPosition + const Duration(seconds: 10),
    );
  }

  Future<void> _expandToMain(BuildContext context, WidgetRef ref) async {
    final mediaService = ref.read(mediaPlayerServiceProvider.notifier);
    final live = mediaService.currentLive;
    final postId = mediaService.currentPostId ?? '';

    mediaService.changeState(MediaPlayerState.main);

    if (context.mounted) {
      // Only navigate if not already on the correct page
      final currentPath = GoRouterState.of(context).uri.path;

      // Check if we're already on the target post/live page
      if (!currentPath.contains(postId)) {
        if (live) {
          context.go('/live/$postId');
        } else if (mediaService.isOffline) {
          // For offline videos, pass the offline data as extras
          context.go('/post/$postId', extra: {
            'isOffline': true,
            'offlinePost': mediaService.offlinePost,
            'offlineAttachmentId': mediaService.offlineAttachmentId,
            'offlineFilePath': mediaService.offlineFilePath,
          });
        } else {
          context.go('/post/$postId');
        }
      }
      // If already on the correct page, state change is enough - the page will rebuild
    }
  }

  void _closePlayer(MediaPlayerService mediaService) {
    mediaService.changeState(MediaPlayerState.none);
    mediaService.stop();
    mediaService.changeState(MediaPlayerState.none);
  }
}

/// Shows the mini player by changing the media player state.
/// The actual mini player widget is rendered in root_layout based on state.
void showMiniPlayer(WidgetRef ref) {
  final mediaService = ref.read(mediaPlayerServiceProvider.notifier);
  mediaService.changeState(MediaPlayerState.mini);
}

/// Hides the mini player by changing state back to main or none.
void hideMiniPlayer(WidgetRef ref, {bool stopPlayback = false}) {
  final mediaService = ref.read(mediaPlayerServiceProvider.notifier);
  if (stopPlayback) {
    mediaService.stop();
    mediaService.changeState(MediaPlayerState.none);
  } else {
    mediaService.changeState(MediaPlayerState.main);
  }
}
