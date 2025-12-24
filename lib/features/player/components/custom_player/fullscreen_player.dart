import 'dart:io';

import 'package:floaty/features/api/models/definitions.dart';
import 'package:floaty/features/player/components/custom_player/custom_player.dart';
import 'package:floaty/features/player/controllers/media_player_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

/// A fullscreen wrapper that overlays the existing video player without recreating it.
/// This approach mirrors how media_kit and better_player handle fullscreen:
/// - Push a new route with rootNavigator to overlay everything
/// - Reuse the same video widget/controller to avoid resetting playback
/// - Handle system UI and orientation changes
/// - On desktop, use window_manager for true fullscreen
class FullscreenPlayerPage extends ConsumerStatefulWidget {
  final Widget video;
  final bool isDesktop;
  final ImageModel? thumbnailSprite;
  final bool pipAvailable;
  final bool wasMaximized;

  const FullscreenPlayerPage({
    super.key,
    required this.video,
    required this.isDesktop,
    this.thumbnailSprite,
    this.pipAvailable = false,
    this.wasMaximized = false,
  });

  @override
  ConsumerState<FullscreenPlayerPage> createState() =>
      _FullscreenPlayerPageState();
}

class _FullscreenPlayerPageState extends ConsumerState<FullscreenPlayerPage> {
  @override
  void initState() {
    super.initState();
    // Fullscreen mode is entered BEFORE navigation in enterFullscreen()
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _exitFullscreenMode() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // Desktop: Exit fullscreen via window_manager
      await windowManager.setFullScreen(false);
      // Restore maximized state if it was maximized before
      if (widget.wasMaximized) {
        await windowManager.maximize();
      }
    } else {
      // Mobile: Disable wakelock
      await WakelockPlus.disable();
      // Mobile: Restore system UI
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      // Restore orientations
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaService = ref.read(mediaPlayerServiceProvider.notifier);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // Exit fullscreen mode BEFORE navigation for smoother transition
        await _exitFullscreenMode();
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: CustomPlayer(
          video: widget.video,
          isDesktop: widget.isDesktop,
          isFullscreen: true,
          showFullscreenButton: true,
          showSettingsButton: true,
          thumbnailSprite:
              widget.thumbnailSprite ?? mediaService.currentTimelineSprite,
          pipAvailable: widget.pipAvailable,
        ),
      ),
    );
  }
}

/// Enters fullscreen mode by pushing a new route with rootNavigator.
/// This overlays the fullscreen player on top of everything without
/// affecting the underlying navigation stack.
Future<void> enterFullscreen(
  BuildContext context, {
  required Widget video,
  required bool isDesktop,
  ImageModel? thumbnailSprite,
  bool pipAvailable = false,
}) async {
  if (!context.mounted) return;

  bool wasMaximized = false;

  // Set up fullscreen mode BEFORE navigation for smoother transition
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // Desktop: Use window_manager for true fullscreen
    wasMaximized = await windowManager.isMaximized();
    await windowManager.setFullScreen(true);
  } else {
    // Mobile: Enable wakelock to keep screen on
    await WakelockPlus.enable();
    // Mobile: Hide system UI for immersive experience
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // On mobile, prefer landscape for video
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  if (!context.mounted) return;

  await Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: true,
      barrierColor: Colors.black,
      pageBuilder: (context, animation, secondaryAnimation) {
        return FullscreenPlayerPage(
          video: video,
          isDesktop: isDesktop,
          thumbnailSprite: thumbnailSprite,
          pipAvailable: pipAvailable,
          wasMaximized: wasMaximized,
        );
      },
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    ),
  );
}

/// Exits fullscreen mode by popping the current route.
Future<void> exitFullscreen(BuildContext context) async {
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).maybePop();
}

/// Toggles fullscreen mode.
Future<void> toggleFullscreen(
  BuildContext context, {
  required bool isCurrentlyFullscreen,
  required Widget video,
  required bool isDesktop,
  ImageModel? thumbnailSprite,
  bool pipAvailable = false,
}) async {
  if (isCurrentlyFullscreen) {
    await exitFullscreen(context);
  } else {
    await enterFullscreen(
      context,
      video: video,
      isDesktop: isDesktop,
      thumbnailSprite: thumbnailSprite,
      pipAvailable: pipAvailable,
    );
  }
}
