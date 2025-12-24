import 'package:floaty/features/player/components/custom_player/custom_player.dart';
import 'package:floaty/whitelabels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:simple_pip_mode/pip_widget.dart';
import 'dart:io' show Platform;
import 'package:window_manager/window_manager.dart';
import 'package:floaty/features/player/controllers/media_player_service.dart';
import 'package:floaty/features/api/repositories/fpapi.dart';

class PipPlayerWidget extends ConsumerWidget {
  final Widget widget;
  final String postId;
  final bool live;

  const PipPlayerWidget(
      {super.key,
      required this.widget,
      required this.postId,
      required this.live});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaService = ref.read(mediaPlayerServiceProvider.notifier);
    return Material(
        child: DragToMoveArea(
      child: Platform.isWindows || Platform.isLinux || Platform.isMacOS
          ?
          // MaterialCustomButton(
          //   icon: Icon(Icons.arrow_back),
          //   onPressed: () async {
          //     mediaService.pipfalse();
          //     if (!live) {
          //       fpApiRequests.iprogress(
          //         (await whitelabels.getSelectedWhitelabel())
          //             .friendlyName,
          //         mediaService.currentAttachmentId ?? '',
          //         mediaService.currentPosition.inSeconds,
          //         mediaService.selectedMediaName ?? '',
          //       );
          //     }
          //     mediaService.changeState(MediaPlayerState.main);
          //     if (live) {
          //       context.go('/live/$postId');
          //     } else {
          //       context.go('/post/$postId');
          //     }
          //   },
          // ),
          // const Spacer(),
          // MaterialCustomButton(
          //   icon: Icon(Icons.close),
          //   onPressed: () {
          //     windowManager.close();
          //   },
          // ),

          CustomPlayer(
              key: ValueKey(postId),
              isDesktop: true,
              video: widget,
              thumbnailSprite: mediaService.currentTimelineSprite,
              pipAvailable: true,
              topControlsOverride: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () async {
                    mediaService.pipfalse();
                    if (!live) {
                      fpApiRequests.iprogress(
                        (await whitelabels.getSelectedWhitelabel())
                            .friendlyName,
                        mediaService.currentAttachmentId ?? '',
                        mediaService.currentPosition.inSeconds,
                        mediaService.selectedMediaName ?? '',
                      );
                    }
                    mediaService.changeState(MediaPlayerState.main);
                    if (live) {
                      context.go('/live/$postId');
                    } else {
                      context.go('/post/$postId');
                    }
                  },
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () {
                    windowManager.close();
                  },
                ),
              ],
            )
          : PipWidget(
              onPipExited: () async {
                fpApiRequests.iprogress(
                  (await whitelabels.getSelectedWhitelabel()).friendlyName,
                  mediaService.currentAttachmentId ?? '',
                  mediaService.currentPosition.inSeconds,
                  mediaService.selectedMediaName ?? '',
                );
                context.go('/post/$postId');
              },
              pipChild: widget,
              child: const Center(child: CircularProgressIndicator()),
            ),
    ));
  }
}
