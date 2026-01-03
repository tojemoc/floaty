import 'dart:async';
import 'dart:io';

import 'package:floaty/features/api/models/definitions.dart';
import 'package:floaty/features/api/repositories/fpapi.dart';
import 'package:floaty/features/player/components/custom_player/custom_player.dart';
import 'package:floaty/features/player/controllers/media_player_service.dart';
import 'package:floaty/whitelabels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop PiP overlay that uses window_manager for always-on-top floating window.
class DesktopPipOverlay extends ConsumerStatefulWidget {
  final Widget video;
  final String postId;
  final bool live;
  final ImageModel? thumbnailSprite;

  const DesktopPipOverlay({
    super.key,
    required this.video,
    required this.postId,
    required this.live,
    this.thumbnailSprite,
  });

  @override
  ConsumerState<DesktopPipOverlay> createState() => _DesktopPipOverlayState();
}

class _DesktopPipOverlayState extends ConsumerState<DesktopPipOverlay> {
  Size? _restoreSize;
  bool _wasMaximized = false;

  @override
  void initState() {
    super.initState();
    _enterPipMode();
  }

  Future<void> _enterPipMode() async {
    _restoreSize = await windowManager.getSize();
    _wasMaximized = await windowManager.isMaximized();

    if (_wasMaximized) {
      await windowManager.unmaximize();
    }

    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSize(const Size(480, 270));
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
  }

  Future<void> _exitPipMode() async {
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);

    if (_restoreSize != null) {
      await windowManager.setSize(_restoreSize!);
    }

    if (_wasMaximized) {
      await windowManager.maximize();
    } else {
      await windowManager.center();
    }
  }

  Future<void> _exitToMain() async {
    final mediaService = ref.read(mediaPlayerServiceProvider.notifier);

    await _exitPipMode();
    mediaService.pipfalse();

    if (!widget.live) {
      fpApiRequests.iprogress(
        (await whitelabels.getSelectedWhitelabel()).friendlyName,
        mediaService.currentAttachmentId ?? '',
        mediaService.currentPosition.inSeconds,
        mediaService.selectedMediaName ?? '',
        isOffline: mediaService.isOffline,
      );
    }

    mediaService.changeState(MediaPlayerState.main);

    if (mounted) {
      Navigator.of(context, rootNavigator: true).maybePop();

      final currentPath = GoRouterState.of(context).uri.path;
      final targetPath =
          widget.live ? '/live/${widget.postId}' : '/post/${widget.postId}';

      if (!currentPath.startsWith(targetPath.split('/').take(2).join('/')) ||
          !currentPath.contains(widget.postId)) {
        if (widget.live) {
          context.go('/live/${widget.postId}');
        } else {
          context.go('/post/${widget.postId}');
        }
      }
    }
  }

  Future<void> _closePlayer() async {
    await windowManager.close();
  }

  @override
  Widget build(BuildContext context) {
    final mediaService = ref.read(mediaPlayerServiceProvider.notifier);

    return Material(
      child: DragToMoveArea(
        child: CustomPlayer(
          key: ValueKey('pip-${widget.postId}'),
          isDesktop: true,
          video: widget.video,
          thumbnailSprite:
              widget.thumbnailSprite ?? mediaService.currentTimelineSprite,
          pipAvailable: false,
          showFullscreenButton: false,
          topControlsOverride: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: _exitToMain,
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: _closePlayer,
            ),
          ],
        ),
      ),
    );
  }
}

/// Enters desktop PiP mode
Future<void> enterDesktopPip(
  BuildContext context, {
  required Widget video,
  required String postId,
  required bool live,
  ImageModel? thumbnailSprite,
}) async {
  if (!context.mounted) return;

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: true,
        barrierColor: Colors.black,
        pageBuilder: (context, animation, secondaryAnimation) {
          return DesktopPipOverlay(
            video: video,
            postId: postId,
            live: live,
            thumbnailSprite: thumbnailSprite,
          );
        },
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }
}

// PiP overlay page that handles its own pipExitStream subscription in initState
// so the subscription lifecycle is tied to the pushed route.
class PiPOverlayPage extends StatefulWidget {
  const PiPOverlayPage({super.key, this.video, required this.mediaService});

  final Widget? video;
  final MediaPlayerService mediaService;

  @override
  State<PiPOverlayPage> createState() => _PiPOverlayPageState();
}

class _PiPOverlayPageState extends State<PiPOverlayPage> {
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.mediaService.pipExitStream.listen((_) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context, rootNavigator: true).maybePop();
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.video ?? const SizedBox.shrink();
  }
}
