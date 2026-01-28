import 'dart:async';
import 'dart:io';
import 'package:floaty/features/api/models/definitions.dart';
import 'package:floaty/features/player/components/custom_player/custom_seekbar.dart';
import 'package:floaty/features/player/components/custom_player/fullscreen_player.dart';
import 'package:floaty/features/player/components/custom_player/pip_overlay.dart';
import 'package:floaty/features/player/controllers/media_player_service.dart';
import 'package:floaty/features/player/models/video_quality.dart';
import 'package:floaty/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:floaty/features/player/models/subtitle_style.dart';
import 'package:language_code/language_code.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

// 1. Define Intents for player actions
class PlayPauseIntent extends Intent {
  const PlayPauseIntent();
}

class SeekForwardIntent extends Intent {
  const SeekForwardIntent();
}

class SeekBackwardIntent extends Intent {
  const SeekBackwardIntent();
}

class VolumeUpIntent extends Intent {
  const VolumeUpIntent();
}

class VolumeDownIntent extends Intent {
  const VolumeDownIntent();
}

class ToggleFullscreenIntent extends Intent {
  const ToggleFullscreenIntent();
}

// 2. Define Actions that respond to the Intents
class PlayPauseAction extends Action<PlayPauseIntent> {
  PlayPauseAction(this.mediaService);
  final MediaPlayerService mediaService;
  @override
  void invoke(PlayPauseIntent intent) {
    mediaService.playpause();
  }
}

class SeekForwardAction extends Action<SeekForwardIntent> {
  SeekForwardAction(this.mediaService);
  final MediaPlayerService mediaService;
  @override
  void invoke(SeekForwardIntent intent) {
    if (mediaService.currentPosition.inSeconds <
        mediaService.currentDuration.inSeconds) {
      mediaService
          .seek(Duration(seconds: mediaService.currentPosition.inSeconds + 5));
    } else {
      mediaService.seek(mediaService.currentDuration);
    }
  }
}

class SeekBackwardAction extends Action<SeekBackwardIntent> {
  SeekBackwardAction(this.mediaService);
  final MediaPlayerService mediaService;
  @override
  void invoke(SeekBackwardIntent intent) {
    if (mediaService.currentPosition.inSeconds > 5) {
      mediaService
          .seek(Duration(seconds: mediaService.currentPosition.inSeconds - 5));
    } else {
      mediaService.seek(Duration.zero);
    }
  }
}

class VolumeUpAction extends Action<VolumeUpIntent> {
  VolumeUpAction(this.mediaService);
  final MediaPlayerService mediaService;
  @override
  void invoke(VolumeUpIntent intent) {
    if (mediaService.volumeLevel < 1.0) {
      mediaService.setVolume((mediaService.volumeLevel + 0.1).clamp(0.0, 1.0));
    }
  }
}

class VolumeDownAction extends Action<VolumeDownIntent> {
  VolumeDownAction(this.mediaService);
  final MediaPlayerService mediaService;
  @override
  void invoke(VolumeDownIntent intent) {
    if (mediaService.volumeLevel > 0.0) {
      mediaService.setVolume((mediaService.volumeLevel - 0.1).clamp(0.0, 1.0));
    }
  }
}

class ToggleFullscreenAction extends Action<ToggleFullscreenIntent> {
  ToggleFullscreenAction(this.onToggleFullscreen);
  final VoidCallback onToggleFullscreen;
  @override
  void invoke(ToggleFullscreenIntent intent) {
    onToggleFullscreen();
  }
}

class CustomPlayer extends ConsumerStatefulWidget {
  final Widget? video;
  final bool isDesktop;
  final bool isFullscreen;
  final bool showFullscreenButton;
  final bool showSettingsButton;
  final ImageModel? thumbnailSprite;
  final bool pipAvailable;
  final List<Widget>? topControlsOverride;
  const CustomPlayer({
    super.key,
    this.video,
    required this.isDesktop,
    this.isFullscreen = false,
    this.showFullscreenButton = true,
    this.showSettingsButton = true,
    this.thumbnailSprite,
    this.pipAvailable = false,
    this.topControlsOverride,
  });
  @override
  ConsumerState<CustomPlayer> createState() => _CustomPlayerState();
}

enum _SubtitleStyleMenu { main, size, weight, opacity, color }

enum _SettingsMenu { main, speed, quality, subtitles, subtitlesStyle }

class _CustomPlayerState extends ConsumerState<CustomPlayer>
    with TickerProviderStateMixin {
  bool _showControls = true;
  bool _isPlaying = true;
  bool _showSettings = false;
  bool _settingsWereOpen = false;
  _SettingsMenu _currentSettingsMenu = _SettingsMenu.main;
  _SubtitleStyleMenu _currentSubtitleStyleMenu = _SubtitleStyleMenu.main;
  bool _shouldShowControls =
      true; // Controls whether controls are in the widget tree
  bool _showVolumeSlider = false;
  double _volume = 0.5;
  Duration _position = Duration.zero;
  Duration _buffered = Duration.zero;
  Duration _duration = const Duration(minutes: 0);
  bool _seekbarDragging = false;
  bool _volumeDragging = false;
  bool _buffering = false;
  double _playbackSpeed = 1.0;
  bool _incrementPlaybackSpeed = false;
  late final AnimationController _animationController;
  Timer? _hideControlsTimer;
  late final MediaPlayerService mediaService;
  void _hideControls() {
    if (mounted && (_showControls || _showSettings)) {
      setState(() {
        _settingsWereOpen = _showSettings;
        _showControls = false;
        _showSettings = false;
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            setState(() => _shouldShowControls = false);
          }
        });
      });
    }
  }

  void _startHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      _hideControls();
    });
  }

  void _handleHover(PointerEvent _) {
    if (!_shouldShowControls) {
      setState(() => _shouldShowControls = true);
      // Small delay to ensure the widget is built before starting animation
      Future.delayed(const Duration(milliseconds: 16), () {
        if (mounted) {
          setState(() {
            _showControls = true;
            if (_settingsWereOpen) {
              _showSettings = true; // Restore settings panel
            }
          });
          _startHideTimer();
        }
      });
    } else if (!_showControls) {
      setState(() {
        _showControls = true;
        if (_settingsWereOpen) {
          _showSettings = true; // Restore settings panel
        }
      });
      _startHideTimer();
    } else {
      _startHideTimer(); // Reset the hide timer on hover
    }
  }

  void _handleExit(PointerEvent _) {
    _hideControlsTimer?.cancel();
    if (_showControls || _showSettings) {
      setState(() {
        _settingsWereOpen = _showSettings; // Remember if settings were open
        _showControls = false;
        _showSettings = false;
      });
      // Schedule removal from widget tree after fade-out animation
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          setState(() => _shouldShowControls = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _tapResetTimer?.cancel();
    _hideIndicatorTimer?.cancel();
    _pipExitSubscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    mediaService = ref.read(mediaPlayerServiceProvider.notifier);

    // Initialize all state from media service to preserve state across widget recreations
    // (e.g., fullscreen, PiP, returning from mini player)
    _volume = mediaService.volumeLevel;
    _position = mediaService.currentPosition;
    _duration = mediaService.currentDuration;
    _buffered = mediaService.buffer;
    _isPlaying = mediaService.isPlaying;
    _playbackSpeed = mediaService.playbackSpeed;
    _buffering = mediaService.buffering;

    _setupPlayerListeners();

    // Perform async initialization without making initState async.
    _asyncInit();
  }

  Future<void> _asyncInit() async {
    _incrementPlaybackSpeed =
        await settings.getBool('increment_playback_speed');
    await _initBrightnessAndVolume();
  }

  Future<void> _initBrightnessAndVolume() async {
    try {
      // Use system brightness for consistency with volume
      _currentBrightness = await ScreenBrightness().system;
    } catch (e) {
      _currentBrightness = 0.5;
    }
    try {
      VolumeController.instance.showSystemUI = false;
      _currentVolume = await VolumeController.instance.getVolume();
    } catch (e) {
      _currentVolume = 0.5;
    }
  }

  void _setupPlayerListeners() {
    // Listen to player state changes
    mediaService.positionStream.listen((position) {
      if (mounted && !_seekbarDragging) {
        setState(() => _position = position);
      }
    });
    mediaService.playbackSpeedStream.listen((speed) {
      if (mounted) {
        setState(() => _playbackSpeed = speed);
      }
    });
    mediaService.durationStream.listen((duration) {
      if (mounted) {
        setState(() => _duration = duration);
      }
    });
    mediaService.volumeStream.listen((volume) {
      if (mounted && !_volumeDragging) {
        setState(() => _volume = volume);
      }
    });
    mediaService.playingStream.listen((playing) {
      if (mounted) {
        setState(() => _isPlaying = playing);
      }
    });
    mediaService.bufferStream.listen((buffered) {
      if (mounted) {
        setState(() => _buffered = buffered);
      }
    });
    mediaService.bufferingStream.listen((buffering) {
      if (mounted) {
        setState(() => _buffering = buffering);
      }
    });
  }

  // Touch gesture detection
  final bool _isSeeking = false;
  // Tap to seek
  int _leftTapCount = 0;
  int _rightTapCount = 0;
  Timer? _tapResetTimer;
  bool _showSeekIndicator = false;
  // Gesture controls
  double? _gestureStartY;
  double? _gestureStartValue;
  bool _isAdjustingBrightness = false;
  bool _isAdjustingVolume = false;
  double _currentBrightness = 0.5;
  double _currentVolume = 0.5;
  bool _showBrightnessIndicator = false;
  bool _showVolumeIndicator = false;
  StreamSubscription<bool>? _pipExitSubscription;
  Timer? _hideIndicatorTimer;
  void _handleTapSeek(bool isLeftSide) {
    // Increment tap count
    if (isLeftSide) {
      _leftTapCount++;
    } else {
      _rightTapCount++;
    }
    final totalTaps = _leftTapCount + _rightTapCount;
    // Cancel any existing timer
    _tapResetTimer?.cancel();
    // If this is the first tap, start a 250ms timer
    if (totalTaps == 1) {
      _tapResetTimer = Timer(const Duration(milliseconds: 250), () {
        // After 250ms, if still only one tap
        if (_leftTapCount + _rightTapCount == 1) {
          // Single tap: toggle controls
          if (_shouldShowControls) {
            _hideControls();
          } else {
            setState(() {
              _shouldShowControls = true;
              _showControls = true;
            });
            _startHideTimer();
          }
          // Reset tap counts
          setState(() {
            _leftTapCount = 0;
            _rightTapCount = 0;
          });
        }
      });
      return;
    }
    // If we get here, it's a second or subsequent tap - seek immediately
    setState(() => _showSeekIndicator = true);
    // Calculate total seek: (tap count * 5) - 5 to account for the initiating tap
    // So double tap = (2 * 5) - 5 = 5 seconds
    final totalSeek = (_leftTapCount * -5) + (_rightTapCount * 5);
    final adjustedSeek = totalSeek > 0 ? totalSeek - 5 : totalSeek + 5;
    final newPosition = _position.inSeconds + adjustedSeek;
    final clampedPosition = newPosition.clamp(0, _duration.inSeconds);
    mediaService.seek(Duration(seconds: clampedPosition));
    // Wait a bit for more taps before hiding indicator
    _tapResetTimer = Timer(const Duration(milliseconds: 250), () {
      // Reset state
      setState(() {
        _leftTapCount = 0;
        _rightTapCount = 0;
        _showSeekIndicator = false;
      });
    });
  }

  /// Handle tap in the middle area - immediately toggle controls without waiting for double tap timer
  void _handleMiddleTap() {
    // Cancel any existing tap timer
    _tapResetTimer?.cancel();
    // Reset tap counts
    setState(() {
      _leftTapCount = 0;
      _rightTapCount = 0;
      _showSeekIndicator = false;
    });
    // Immediately toggle controls
    if (_shouldShowControls) {
      _hideControls();
    } else {
      setState(() {
        _shouldShowControls = true;
        _showControls = true;
      });
      _startHideTimer();
    }
  }

  void _handleVerticalDragStart(
      DragStartDetails details, bool isLeftSide, double screenWidth) {
    final position = details.localPosition;
    // Cancel tap timer and reset tap counts when drag starts
    _tapResetTimer?.cancel();
    setState(() {
      _leftTapCount = 0;
      _rightTapCount = 0;
      _showSeekIndicator = false;
    });
    // Determine if it's left or right side
    if (isLeftSide) {
      _isAdjustingBrightness = true;
      _gestureStartValue = _currentBrightness;
    } else {
      _isAdjustingVolume = true;
      _gestureStartValue = _currentVolume;
    }
    _gestureStartY = position.dy;
    setState(() {
      if (isLeftSide) {
        _showBrightnessIndicator = true;
      } else {
        _showVolumeIndicator = true;
      }
    });
  }

  void _handleVerticalDragUpdate(
      DragUpdateDetails details, bool isLeftSide, double screenHeight) {
    if (_gestureStartY == null || _gestureStartValue == null) return;
    final deltaY = _gestureStartY! - details.localPosition.dy;
    final sensitivity = 1.0 / (screenHeight * 0.5); // Adjust sensitivity
    final delta = deltaY * sensitivity;
    if (isLeftSide && _isAdjustingBrightness) {
      final newBrightness = (_gestureStartValue! + delta).clamp(0.0, 1.0);
      setState(() => _currentBrightness = newBrightness);
      ScreenBrightness().setApplicationScreenBrightness(newBrightness);
    } else if (!isLeftSide && _isAdjustingVolume) {
      final newVolume = (_gestureStartValue! + delta).clamp(0.0, 1.0);
      setState(() => _currentVolume = newVolume);
      VolumeController.instance.setVolume(newVolume);
    }
  }

  void _handleVerticalDragEnd() {
    _gestureStartY = null;
    _gestureStartValue = null;
    _isAdjustingBrightness = false;
    _isAdjustingVolume = false;
    // Hide indicators after a delay
    _hideIndicatorTimer?.cancel();
    _hideIndicatorTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) {
        setState(() {
          _showBrightnessIndicator = false;
          _showVolumeIndicator = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;
        final isMobile = !widget.isDesktop;
        // Start the hide timer when controls are first shown
        if (_showControls) _startHideTimer();
        final shortcuts = <LogicalKeySet, Intent>{
          LogicalKeySet(LogicalKeyboardKey.space): const PlayPauseIntent(),
          LogicalKeySet(LogicalKeyboardKey.arrowLeft):
              const SeekBackwardIntent(),
          LogicalKeySet(LogicalKeyboardKey.arrowRight):
              const SeekForwardIntent(),
          LogicalKeySet(LogicalKeyboardKey.arrowUp): const VolumeUpIntent(),
          LogicalKeySet(LogicalKeyboardKey.arrowDown): const VolumeDownIntent(),
          LogicalKeySet(LogicalKeyboardKey.keyF):
              const ToggleFullscreenIntent(),
        };
        final actions = <Type, Action<Intent>>{
          PlayPauseIntent: PlayPauseAction(mediaService),
          SeekForwardIntent: SeekForwardAction(mediaService),
          SeekBackwardIntent: SeekBackwardAction(mediaService),
          VolumeUpIntent: VolumeUpAction(mediaService),
          VolumeDownIntent: VolumeDownAction(mediaService),
          ToggleFullscreenIntent: ToggleFullscreenAction(_toggleFullscreen),
        };
        return Shortcuts(
          shortcuts: shortcuts,
          child: Actions(
            actions: actions,
            child: Focus(
              autofocus: true,
              child: MouseRegion(
                onHover: _handleHover,
                onExit: _handleExit,
                child: Stack(
                  children: [
                    // Main content
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      child: Container(
                        color: Colors.black,
                        child: Stack(
                          fit: widget.isFullscreen
                              ? StackFit.expand
                              : StackFit.passthrough,
                          children: [
                            // Video display
                            Positioned.fill(
                              child: Center(
                                child: AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: _buildVideoPlayer(),
                                ),
                              ),
                            ),
                            // Custom subtitles overlay (always in tree)
                            AnimatedPositioned(
                              left: 12,
                              right: 12,
                              bottom: (() {
                                final controlsVisible = _shouldShowControls &&
                                    (_showControls || _showSettings);
                                if (controlsVisible) {
                                  return widget.isFullscreen ? 110.0 : 72.0;
                                } else {
                                  return widget.isFullscreen ? 56.0 : 28.0;
                                }
                              }()),
                              duration: const Duration(milliseconds: 100),
                              curve: Curves.easeInOut,
                              child: IgnorePointer(
                                child: StreamBuilder<String?>(
                                  stream: mediaService.subtitleTextStream,
                                  builder: (context, snapshot) {
                                    final text = snapshot.data;
                                    final show =
                                        mediaService.subtitlesEnabled &&
                                            text != null &&
                                            text.trim().isNotEmpty;
                                    if (!show) return const SizedBox.shrink();
                                    return Center(
                                      child: ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 900),
                                        child: StreamBuilder<SubtitleStyle>(
                                          stream:
                                              mediaService.subtitleStyleStream,
                                          initialData:
                                              mediaService.currentSubtitleStyle,
                                          builder: (context, styleSnap) {
                                            final style = styleSnap.data ??
                                                mediaService
                                                    .currentSubtitleStyle;
                                            return Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(
                                                    alpha: style
                                                        .backgroundOpacity),
                                                borderRadius:
                                                    BorderRadius.circular(2),
                                              ),
                                              child: Text(
                                                text,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: style.color,
                                                  fontSize: style.fontSize,
                                                  fontWeight: style.fontWeight,
                                                  height: 1.3,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            // Controls overlay - Only in widget tree when needed
                            if (_shouldShowControls)
                              _buildControlsOverlay(mediaService,
                                  isLandscape: isLandscape),
                            // Seek indicator for mobile
                            if (_isSeeking && isMobile)
                              Positioned(
                                left: 0,
                                right: 0,
                                top: 0,
                                bottom: 0,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      _formatDuration(_position),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            // Tap to seek indicator
                            if (_showSeekIndicator && isMobile)
                              Positioned(
                                left: 0,
                                right: 0,
                                top: 0,
                                bottom: 0,
                                child: IgnorePointer(
                                  child: Row(
                                    children: [
                                      // Left side indicator
                                      if (_leftTapCount > 0)
                                        Expanded(
                                          child: Container(
                                            alignment: Alignment.center,
                                            child: Container(
                                              padding: const EdgeInsets.all(20),
                                              decoration: BoxDecoration(
                                                color: Colors.black
                                                    .withValues(alpha: 0.6),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.fast_rewind,
                                                    color: Colors.white,
                                                    size: 40,
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    '${(_leftTapCount * 5) - 5} sec',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        )
                                      else
                                        const Spacer(),
                                      const Spacer(),
                                      // Right side indicator
                                      if (_rightTapCount > 0)
                                        Expanded(
                                          child: Container(
                                            alignment: Alignment.center,
                                            child: Container(
                                              padding: const EdgeInsets.all(20),
                                              decoration: BoxDecoration(
                                                color: Colors.black
                                                    .withValues(alpha: 0.6),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.fast_forward,
                                                    color: Colors.white,
                                                    size: 40,
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    '${(_rightTapCount * 5) - 5} sec',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        )
                                      else
                                        const Spacer(),
                                    ],
                                  ),
                                ),
                              ),
                            // Brightness indicator
                            if (_showBrightnessIndicator && isMobile)
                              Positioned(
                                top: 40,
                                left: 0,
                                right: 0,
                                child: IgnorePointer(
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.black.withValues(alpha: 0.7),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.brightness_6,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          SizedBox(
                                            width: 100,
                                            child: LinearProgressIndicator(
                                              value: _currentBrightness,
                                              backgroundColor: Colors.white24,
                                              valueColor:
                                                  const AlwaysStoppedAnimation<
                                                      Color>(Colors.white),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            '${(_currentBrightness * 100).round()}%',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            // Volume indicator
                            if (_showVolumeIndicator && isMobile)
                              Positioned(
                                top: 40,
                                left: 0,
                                right: 0,
                                child: IgnorePointer(
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.black.withValues(alpha: 0.7),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _currentVolume == 0
                                                ? Icons.volume_off
                                                : _currentVolume < 0.5
                                                    ? Icons.volume_down
                                                    : Icons.volume_up,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          SizedBox(
                                            width: 100,
                                            child: LinearProgressIndicator(
                                              value: _currentVolume,
                                              backgroundColor: Colors.white24,
                                              valueColor:
                                                  const AlwaysStoppedAnimation<
                                                      Color>(Colors.white),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            '${(_currentVolume * 100).round()}%',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // Tap detectors - full screen when hidden, safe zones when visible
                    if (isMobile) ...[
                      if (!_shouldShowControls) ...[
                        // Full screen tap + swipe detector when controls are hidden
                        Positioned.fill(
                          child: Row(
                            children: [
                              // Left third - seek backward + brightness swipe
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (details) => _handleTapSeek(true),
                                  onVerticalDragStart: (details) =>
                                      _handleVerticalDragStart(
                                          details, true, constraints.maxWidth),
                                  onVerticalDragUpdate: (details) =>
                                      _handleVerticalDragUpdate(
                                          details, true, constraints.maxHeight),
                                  onVerticalDragEnd: (_) =>
                                      _handleVerticalDragEnd(),
                                ),
                              ),
                              // Middle third - immediately toggle controls (no timer)
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (details) => _handleMiddleTap(),
                                ),
                              ),
                              // Right third - seek forward + volume swipe
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (details) => _handleTapSeek(false),
                                  onVerticalDragStart: (details) =>
                                      _handleVerticalDragStart(
                                          details, false, constraints.maxWidth),
                                  onVerticalDragUpdate: (details) =>
                                      _handleVerticalDragUpdate(details, false,
                                          constraints.maxHeight),
                                  onVerticalDragEnd: (_) =>
                                      _handleVerticalDragEnd(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // Safe zones when controls are visible (avoid top/bottom bars)
                        // Only left and right sides for double-tap seek
                        // Middle area is NOT covered so play/pause button can be tapped
                        // Left side
                        Positioned(
                          left: 0,
                          top: 80,
                          bottom: 120,
                          width: constraints.maxWidth * 0.3,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (details) => _handleTapSeek(true),
                          ),
                        ),
                        // Right side
                        Positioned(
                          right: 0,
                          top: 80,
                          bottom: 120,
                          width: constraints.maxWidth * 0.3,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (details) => _handleTapSeek(false),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoPlayer() {
    return widget.video!;
  }

  Widget _buildControlsOverlay(MediaPlayerService mediaService,
      {required bool isLandscape}) {
    final isMobile = !widget.isDesktop;
    return AnimatedOpacity(
      opacity: _showControls || _showSettings ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.6),
              Colors.transparent,
              Colors.transparent,
              Colors.transparent,
              Colors.transparent,
              Colors.transparent,
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.6),
            ],
          ),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top bar
                _buildTopBar(mediaService),
                // Center controls (only for fullscreen/mobile)
                if (_buffering)
                  Expanded(
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  )
                else
                  Expanded(
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          if (isMobile || !_isPlaying) ...[
                            _buildControlButton(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              () => mediaService.playpause(),
                              size: 45,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                _buildBottomBar(
                  isLandscape: isLandscape,
                ),
              ],
            ),
            // Settings panel within overlay so it participates in overlay animation & gradient
            if (_showSettings) _buildSettingsPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(MediaPlayerService mediaService) {
    final isMobile = !widget.isDesktop;
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: widget.topControlsOverride ??
            [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () async {
                  mediaService.changeState(MediaPlayerState.none);
                  mediaService.stop();
                  if (widget.isFullscreen) {
                    // In fullscreen: first exit fullscreen overlay, then pop the underlying page
                    Navigator.of(context, rootNavigator: true).pop();
                    // Small delay to ensure fullscreen is closed first
                    await Future.delayed(const Duration(milliseconds: 50));
                    if (context.mounted) {
                      Navigator.of(context, rootNavigator: true).maybePop();
                    }
                  } else {
                    Navigator.maybePop(context);
                  }
                },
              ),
              const Spacer(),
              // Settings button on mobile
              if (isMobile)
                IconButton(
                  icon: const Icon(Icons.settings, color: Colors.white),
                  onPressed: _toggleSettings,
                ),
            ],
      ),
    );
  }

  Widget _buildBottomBar({required bool isLandscape}) {
    final isMobile = !widget.isDesktop;
    final chapters = mediaService.chapters;
    // // Parse chapters once and compute current chapter title
    // final chapters = mediaService.parseSeekbarChapters(r'''
    //               [0:00] Chapters. [2:10] Intro. [2:54] Topic #1: Trump's 100% tech tariffs, demands Intel's CEO to step down. > 4:07 Foxconn, Pal Gelsinger & hockey analogy, Intel & AMD. > 16:45 Less amount of Las Vegas tourism, gambling, airline layoffs. > 21:11 Recession, West Edmonton mall, luxury goods, Linus's brother. > 38:02 "I'm not gay," water park. [42:10] Topic #2: AI topics. > 42:22 Google DeepMind's Genie 3. > 45:14 OpenAI's free GPT models, ChatGPT-5. > 51:55 "ChatGPT lies," MM on Luke's DualSense, Dan's response. > 57:50 Training a model on WAN Show transcript for MM? > 59:35 Luke on why ChatGPT-5 was more interesting than 4/4o. > 1:00:23 Anthropic's Claude Opus 4.1, Elevenlabs's AI generated music. > 1:06:45 Twitter's Grok AI will now have built in ads. > 1:09:43 Luke on LTT's upcoming vibe coding video. [1:12:17] LTTStore's new CPU fidget spinner. > 1:15:13 Taking off the spinner to replace it. [1:17:15] Merch Message #1. > 1:18:02 Why did LTT go for orange? ft. Scrapyard wars. [1:21:12] LTTStore's new screwdriver grip tape. > 1:25:36 LTTStore's new sticker pack. [1:27:16] Topic #3: $3.5m tech jet plane? > 1:29:39 Another jet listing, old laptop, photo staging, limited quantity. [1:39:48] Sponsors ft. Spinning the CPU the whole time. > 1:40:08 Odoo. > 1:41:05 Proton. > 1:41:55 Vessi. [1:43:44] LibreDrive's firmware hack for BLU-ray drives ft. Edmonton. [1:49:23] Scrapyard Wars 10 going live on FP. > 1:50:47 Upcoming extras & BTS footage, FP x Sarah stream. [1:52:15] Topic #4: Tesla autopilot partially liable in a lethal crash. > 1:59:26 Luke on a company using on premise servers for LLMs. > 2:03:34 Would AI have a real impact on health? ft. Lina Khan. [2:06:21] Topic #5: Ubiquiti's UniFi OS server can be ran on PC hardware. [2:09:26] Topic #6: Google claims AI summary doesn't reduce site clicks. > 2:12:11 TMB, blockchain, "post-COVID sources," search engines. > 2:15:32 Linus runs GrapheneOS, DuckDuckGo, Luke on spam calls. [2:21:01] Topic #7: Genshin Impact discontinued on PS4. > 2:30:53 Among Us was a spin-off, Hand and Foot & Canasta. [2:34:23] Topic #8: Instagram added Maps with locations on by default. [2:38:39] Topic #9: Microsoft's vision of computing in 2030. [2:41:47] Topic #10: Digital Foundry bought back & goes independent. > 2:43:12 Freedoms LTT has as an independent media? > 2:55:46 Why does Gaben get a billionaire pass? ft. Amazon, Operah. > 3:04:44 FP poll: Gamer jet or gamer yacht? Gamer ski lift. [3:07:32] Topic #11: Nvidia's chips don't have backdoors or kill switches. [3:07:58] Topic #12: TikTok Pro & Sunshine programme. [3:10:26] Merch Messages #2 ft. After Dark, Luke turns purple. > 3:12:22 How much minimum storage is needed in 2025? > 3:13:42 New games you're anticipating? ft. Carpoon. > 3:16:46 Flagrant case of corruption you've seen in Vancouver? > 3:17:48 Thoughts on wealth flexing YTbers & kids? ft. Weird AI ad. > 3:29:14 Has Luke seen Paco the Parrot? > 3:31:12 LTT bits influenced Hacksmith's mutlitool ft. Colebar. > 3:36:27 What made LTT backpack have an internal bottle holder? > 3:37:57 How did LTT get this many CPUs for the spinner? > 3:38:42 Does Linus teach his kids about online safety? > 3:39:20 Linus's badminton shoes wear. > 3:40:07 Why is there no 24-25 Zenbook Duo laptop reviews? > 3:41:28 As a grinder, what helps Luke relax & feel better? > 3:43:53 Did Linus intend to make the meme face, or he had a resting one? > 3:45:02 Will Linus encourage his kids to pursue education & work? > 3:49:46 Linus's thoughts on working on the hobby farm as an adult? > 3:52:05 Given the Z Fold 7, will Linus daily drive a foldable again? > 3:52:33 Furthest you traveled to view or buy a product? [3:56:33] Outro.
    //             ''');
    String? currentChapterTitle;
    if (chapters != null && chapters.isNotEmpty) {
      final curSec = _position.inSeconds.toDouble();
      for (int i = chapters.length - 1; i >= 0; i--) {
        final startSec = chapters[i].start.inSeconds.toDouble();
        if (curSec >= startSec) {
          currentChapterTitle = chapters[i].title;
          break;
        }
      }
    }
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // absorb taps so parent onTap (play/pause) doesn't fire
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: isLandscape ? 12.0 : 8.0,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 1),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // On mobile non-fullscreen: buttons first, seekbar last
            // Otherwise: seekbar first, buttons last
            if (!mediaService.currentLive && (widget.isFullscreen || !isMobile))
              Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: CustomSeekBar(
                    value: _position.inSeconds.toDouble(),
                    buffered: _buffered.inSeconds.toDouble(),
                    min: 0,
                    max: _duration.inSeconds.toDouble(),
                    activeTrackColor: colorScheme.primary,
                    inactiveTrackColor: Colors.white24,
                    bufferedTrackColor: Colors.white38,
                    thumbColor: Colors.white,
                    trackHeight: 4.0,
                    thumbnailSpriteUrl: widget.thumbnailSprite?.path ??
                        mediaService.currentTimelineSprite?.path,
                    spriteWidth: widget.thumbnailSprite?.width ??
                        mediaService.currentTimelineSprite?.width,
                    spriteHeight: widget.thumbnailSprite?.height ??
                        mediaService.currentTimelineSprite?.height,
                    videoDuration: _duration,
                    previewBuilder: (time) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Builder(builder: (_) {
                          final h = time.inHours;
                          final m = time.inMinutes.remainder(60);
                          final s = time.inSeconds.remainder(60);
                          final mm = m.toString().padLeft(2, '0');
                          final ss = s.toString().padLeft(2, '0');
                          final text = h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
                          return Text(
                            text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        }),
                      );
                    },
                    onChanged: (value) {
                      setState(() {
                        _seekbarDragging = true;
                        _position = Duration(seconds: value.toInt());
                        mediaService.seek(Duration(seconds: value.toInt()));
                      });
                    },
                    onChangeEnd: (value) {
                      _seekbarDragging = false;
                      _position = Duration(seconds: value.toInt());
                    },
                    chapterMarkerWidth: 0,
                    chapterMarkerExtraHeight: 0,
                    chapters: chapters ?? [],
                    chapterGap: 1,
                  )),
            // Bottom controls
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isLandscape ? 28.0 : 18.0,
              ),
              child: SizedBox(
                height: isMobile && !widget.isFullscreen ? 30 : 40,
                child: Row(
                  children: [
                    // Left side controls
                    if (!isMobile) ...[
                      _buildControlButton(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        () => mediaService.playpause(),
                        size: 24,
                      ),
                      const SizedBox(width: 4),
                      _buildVolumeButtonAndSlider(),
                    ],
                    // Time display
                    if (!mediaService.currentLive) ...[
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 0.0 : 12.0,
                        ),
                        child: Text(
                          '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: Text(
                          'LIVE',
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    // Current chapter dot and title (only when chapters exist)
                    if (chapters != null &&
                        chapters.isNotEmpty &&
                        currentChapterTitle != null &&
                        !mediaService.currentLive)
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.circle,
                              size: 6,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                currentChapterTitle,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      const Spacer(),
                    if (widget.pipAvailable) ...[
                      // PiP button
                      _buildControlButton(
                        Icons.picture_in_picture,
                        () async {
                          mediaService.enterpip();
                          await Navigator.of(context, rootNavigator: true).push(
                            PageRouteBuilder(
                              opaque: true,
                              barrierColor: Colors.black,
                              pageBuilder:
                                  (context, animation, secondaryAnimation) {
                                return Platform.isAndroid || Platform.isIOS
                                    ? PiPOverlayPage(
                                        video: widget.video,
                                        mediaService: mediaService,
                                      )
                                    : DesktopPipOverlay(
                                        video: widget.video!,
                                        postId: mediaService.currentPostId!,
                                        live: mediaService.currentLive,
                                        thumbnailSprite: widget.thumbnailSprite,
                                      );
                              },
                              transitionDuration: Duration.zero,
                              reverseTransitionDuration: Duration.zero,
                            ),
                          );
                        },
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (!isMobile && mediaService.textTracks != null) ...[
                      // Subtitles button
                      _buildControlButton(
                        mediaService.subtitlesEnabled
                            ? Icons.subtitles
                            : Icons.subtitles_outlined,
                        mediaService.toggleSubtitles,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (!isMobile)
                      // Settings button (only on desktop or fullscreen)
                      _buildControlButton(
                        Icons.settings,
                        _toggleSettings,
                        size: 24,
                      ),
                    // Fullscreen button
                    if (!isMobile || widget.isFullscreen)
                      const SizedBox(width: 8),
                    _buildControlButton(
                      widget.isFullscreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                      _toggleFullscreen,
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
            // Seekbar at bottom for mobile non-fullscreen
            if (!mediaService.currentLive && isMobile && !widget.isFullscreen)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: CustomSeekBar(
                  value: _position.inSeconds.toDouble(),
                  buffered: _buffered.inSeconds.toDouble(),
                  min: 0,
                  max: _duration.inSeconds.toDouble(),
                  activeTrackColor: colorScheme.primary,
                  inactiveTrackColor: Colors.white24,
                  bufferedTrackColor: Colors.white38,
                  thumbColor: Colors.white,
                  trackHeight: 4.0,
                  thumbnailSpriteUrl: widget.thumbnailSprite?.path,
                  spriteWidth: widget.thumbnailSprite?.width,
                  spriteHeight: widget.thumbnailSprite?.height,
                  videoDuration: _duration,
                  previewBuilder: (time) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Builder(builder: (_) {
                        final h = time.inHours;
                        final m = time.inMinutes.remainder(60);
                        final s = time.inSeconds.remainder(60);
                        final mm = m.toString().padLeft(2, '0');
                        final ss = s.toString().padLeft(2, '0');
                        final text = h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
                        return Text(
                          text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }),
                    );
                  },
                  onChanged: (value) {
                    setState(() {
                      _seekbarDragging = true;
                      _position = Duration(seconds: value.toInt());
                      mediaService.seek(Duration(seconds: value.toInt()));
                    });
                  },
                  onChangeEnd: (value) {
                    _seekbarDragging = false;
                    _position = Duration(seconds: value.toInt());
                  },
                  chapterMarkerWidth: 0,
                  chapterMarkerExtraHeight: 0,
                  chapters: chapters ?? [],
                  chapterGap: 1,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return Positioned(
      right: 16,
      bottom: 80,
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 10,
            ),
          ],
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _buildCurrentMenu(),
        ),
      ),
    );
  }

  Widget _buildMobileSettingsSheet() {
    return StatefulBuilder(
      builder: (context, setModalState) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(16),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Settings content
              Flexible(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildCurrentMenuWithState(setModalState),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCurrentMenuWithState(StateSetter setModalState) {
    // This wrapper allows the bottom sheet to update when menu changes
    return Builder(
      builder: (context) {
        // Reset the subtitle style menu when changing to a different settings menu
        if (_currentSettingsMenu != _SettingsMenu.subtitlesStyle) {
          _currentSubtitleStyleMenu = _SubtitleStyleMenu.main;
        }
        Widget menu;
        switch (_currentSettingsMenu) {
          case _SettingsMenu.main:
            menu = _buildMainMenu(setModalState: setModalState);
            break;
          case _SettingsMenu.speed:
            menu = _buildSpeedMenuWithBack(() {
              _currentSettingsMenu = _SettingsMenu.main;
              setModalState(() {});
            }, setModalState: setModalState);
            break;
          case _SettingsMenu.quality:
            menu = _buildQualityMenuWithBack(() {
              _currentSettingsMenu = _SettingsMenu.main;
              setModalState(() {});
            }, setModalState: setModalState);
            break;
          case _SettingsMenu.subtitles:
            menu = _buildSubtitlesMenuWithBack(() {
              _currentSettingsMenu = _SettingsMenu.main;
              setModalState(() {});
            }, setModalState: setModalState);
            break;
          case _SettingsMenu.subtitlesStyle:
            menu = _buildSubtitlesStyleMenuWithBack(() {
              _currentSettingsMenu = _SettingsMenu.main;
              setModalState(() {});
            }, setModalState: setModalState);
            break;
        }
        return menu;
      },
    );
  }

  Widget _buildCurrentMenu() {
    // Reset the subtitle style menu when changing to a different settings menu
    if (_currentSettingsMenu != _SettingsMenu.subtitlesStyle) {
      _currentSubtitleStyleMenu = _SubtitleStyleMenu.main;
    }
    switch (_currentSettingsMenu) {
      case _SettingsMenu.main:
        return _buildMainMenu();
      case _SettingsMenu.speed:
        return _buildSpeedMenu();
      case _SettingsMenu.quality:
        return _buildQualityMenu();
      case _SettingsMenu.subtitles:
        return _buildSubtitlesMenu();
      case _SettingsMenu.subtitlesStyle:
        return _buildSubtitlesStyleMenu();
    }
  }

  Widget _buildMainMenu({StateSetter? setModalState}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!mediaService.currentLive)
          _buildSettingsMenuItem(
            icon: Icons.speed,
            title: 'Speed',
            value: '${_playbackSpeed}x',
            onTap: () => setModalState != null
                ? setModalState(
                    () => _currentSettingsMenu = _SettingsMenu.speed)
                : setState(() => _currentSettingsMenu = _SettingsMenu.speed),
          ),
        if (!mediaService.isOffline)
          _buildSettingsMenuItem(
            icon: Icons.grid_on,
            title: 'Quality',
            value: mediaService.currentQuality?.label ?? 'Auto',
            onTap: () => setModalState != null
                ? setModalState(
                    () => _currentSettingsMenu = _SettingsMenu.quality)
                : setState(() => _currentSettingsMenu = _SettingsMenu.quality),
          ),
        if (mediaService.textTracks != null) ...[
          _buildSettingsMenuItem(
            icon: Icons.closed_caption,
            title: 'Captions',
            value: mediaService.subtitlesEnabled &&
                    mediaService.currentSubtitleTrackIndex != null &&
                    (mediaService.textTracks?.isNotEmpty ?? false)
                ? (mediaService.textTracks![
                        mediaService.currentSubtitleTrackIndex!]['language'] ??
                    'Unknown')
                : 'Off',
            onTap: () => setModalState != null
                ? setModalState(
                    () => _currentSettingsMenu = _SettingsMenu.subtitles)
                : setState(
                    () => _currentSettingsMenu = _SettingsMenu.subtitles),
          ),
          _buildSettingsMenuItem(
            icon: Icons.subtitles,
            title: 'Captions Style',
            onTap: () => setModalState != null
                ? setModalState(
                    () => _currentSettingsMenu = _SettingsMenu.subtitlesStyle)
                : setState(
                    () => _currentSettingsMenu = _SettingsMenu.subtitlesStyle),
          ),
        ],
      ],
    );
  }

  Widget _buildSpeedMenu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSubMenuHeader('Playback Speed'),
        _buildSpeedOption(0.5),
        _buildSpeedOption(0.75),
        _buildSpeedOption(1.0),
        _buildSpeedOption(1.25),
        _buildSpeedOption(1.5),
        _buildSpeedOption(2.0),
        Material(
          color: Colors.transparent,
          child: InkWell(
            child: Center(
              child: Slider(
                value: _playbackSpeed,
                min: _incrementPlaybackSpeed ? 0.3 : 0.25,
                max: 4.0,
                divisions: _incrementPlaybackSpeed ? 37 : 15,
                label: '${_playbackSpeed.toStringAsFixed(2)}x',
                onChanged: (value) {
                  setState(() => _playbackSpeed = value);
                  mediaService.setSpeed(value);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedMenuWithBack(VoidCallback onBack,
      {StateSetter? setModalState}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSubMenuHeader('Playback Speed', onBack: onBack),
        _buildSpeedOption(0.5, setModalState: setModalState),
        _buildSpeedOption(0.75, setModalState: setModalState),
        _buildSpeedOption(1.0, setModalState: setModalState),
        _buildSpeedOption(1.25, setModalState: setModalState),
        _buildSpeedOption(1.5, setModalState: setModalState),
        _buildSpeedOption(2.0, setModalState: setModalState),
        Material(
          color: Colors.transparent,
          child: InkWell(
            child: Center(
              child: Slider(
                value: _playbackSpeed,
                min: _incrementPlaybackSpeed ? 0.3 : 0.25,
                max: 4.0,
                divisions: _incrementPlaybackSpeed ? 37 : 15,
                label: '${_playbackSpeed.toStringAsFixed(2)}x',
                onChanged: (value) {
                  if (setModalState != null) {
                    setModalState(() => _playbackSpeed = value);
                  } else {
                    setState(() => _playbackSpeed = value);
                  }
                  mediaService.setSpeed(value);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQualityMenu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSubMenuHeader('Quality'),
        ...mediaService.availableQualities.map((q) => _buildQualityOption(q)),
      ],
    );
  }

  Widget _buildQualityMenuWithBack(VoidCallback onBack,
      {StateSetter? setModalState}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSubMenuHeader('Quality', onBack: onBack),
        ...mediaService.availableQualities
            .map((q) => _buildQualityOption(q, setModalState: setModalState)),
      ],
    );
  }

  Widget _buildSubtitlesMenu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSubMenuHeader('Subtitles'),
        _buildSubtitleOption(
          'Off',
          isSelected: !(mediaService.subtitlesEnabled),
          onTap: () async {
            await mediaService.toggleSubtitles(enabled: false);
            setState(() {});
          },
        ),
        if (mediaService.textTracks != null)
          ...mediaService.textTracks!.asMap().entries.map(
                (entry) => _buildSubtitleOption(
                  (LanguageCodes.fromCode(entry.value['language'])).name,
                  isSelected: mediaService.subtitlesEnabled &&
                      mediaService.currentSubtitleTrackIndex == entry.key,
                  isGenerated: entry.value['generated'],
                  isProcessing: entry.value['processing'],
                  onTap: () async {
                    if (entry.value['processing'] == true) {
                      return;
                    }
                    await mediaService.setSubtitleTrack(entry.key);
                    setState(() {});
                  },
                ),
              ),
      ],
    );
  }

  Widget _buildSubtitlesMenuWithBack(VoidCallback onBack,
      {StateSetter? setModalState}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSubMenuHeader('Subtitles', onBack: onBack),
        _buildSubtitleOption(
          'Off',
          isSelected: !(mediaService.subtitlesEnabled),
          onTap: () async {
            await mediaService.toggleSubtitles(enabled: false);
            if (setModalState != null) {
              setModalState(() {});
            } else {
              setState(() {});
            }
          },
        ),
        if (mediaService.textTracks != null)
          ...mediaService.textTracks!.asMap().entries.map(
                (entry) => _buildSubtitleOption(
                  (LanguageCodes.fromCode(entry.value['language'])).name,
                  isSelected: mediaService.subtitlesEnabled &&
                      mediaService.currentSubtitleTrackIndex == entry.key,
                  isGenerated: entry.value['generated'],
                  isProcessing: entry.value['processing'],
                  onTap: () async {
                    if (entry.value['processing'] == true) {
                      return;
                    }
                    await mediaService.setSubtitleTrack(entry.key);
                    if (setModalState != null) {
                      setModalState(() {});
                    } else {
                      setState(() {});
                    }
                  },
                ),
              ),
      ],
    );
  }

  // Default subtitle style values
  static const double _defaultFontSize = 18.0;
  static const FontWeight _defaultFontWeight = FontWeight.bold;
  static const double _defaultBackgroundOpacity = 0.50;
  static const Color _defaultColor = Colors.white;
  Future<void> _resetToDefaultStyle() async {
    await mediaService.setSubtitleFontSize(_defaultFontSize);
    await mediaService.setSubtitleFontWeight(_defaultFontWeight, 'Normal');
    await mediaService.setSubtitleBackgroundOpacity(_defaultBackgroundOpacity);
    await mediaService.setSubtitleColor(_defaultColor);
    setState(() {});
  }

  Widget _buildSubtitlesStyleMenu() {
    final sizes = <String, double>{
      'Small (18px)': 18,
      'Medium (24px)': 24,
      'Large (36px)': 36,
      'Extra Large (42px)': 42,
    };
    final weights = <String, FontWeight>{
      'Extra Light': FontWeight.w200,
      'Light': FontWeight.w300,
      'Medium': FontWeight.w500,
      'Semi Bold': FontWeight.w600,
      'Bold': FontWeight.w700,
    };
    final opacities = <String, double>{
      '0%': 0.0,
      '25%': 0.25,
      '50%': 0.5,
      '75%': 0.75,
      '100%': 1.0,
    };
    final colors = <String, Color>{
      'White': Colors.white,
      'Yellow': Colors.yellow,
      'Cyan': Colors.cyanAccent,
      'Green': Colors.greenAccent,
      'Magenta': Colors.pinkAccent,
      'Red': Colors.redAccent,
      'Black': Colors.black,
    };
    final style = mediaService.currentSubtitleStyle;
    // Show the main style menu
    if (_currentSubtitleStyleMenu == _SubtitleStyleMenu.main) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSubMenuHeader('Captions Style'),
          _buildStyleOption(
            'Font Size',
            icon: Icons.text_fields,
            onTap: () => setState(
                () => _currentSubtitleStyleMenu = _SubtitleStyleMenu.size),
            trailing: Text(
              '${style.fontSize.toInt()}px',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          _buildStyleOption(
            'Font Weight',
            icon: Icons.line_weight,
            onTap: () => setState(
                () => _currentSubtitleStyleMenu = _SubtitleStyleMenu.weight),
            trailing: Text(
              style.fontWeight.toString().split('.').last,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          _buildStyleOption(
            'Background Opacity',
            icon: Icons.opacity,
            onTap: () => setState(
                () => _currentSubtitleStyleMenu = _SubtitleStyleMenu.opacity),
            trailing: Text(
              '${(style.backgroundOpacity * 100).toInt()}%',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          _buildStyleOption(
            'Text Color',
            icon: Icons.color_lens,
            onTap: () => setState(
                () => _currentSubtitleStyleMenu = _SubtitleStyleMenu.color),
            trailing: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: style.color,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: Colors.white24),
              ),
            ),
          ),
          const Divider(color: Colors.white12, height: 8),
          _buildStyleOption(
            'Reset to Default',
            icon: Icons.restart_alt,
            onTap: () async {
              await _resetToDefaultStyle();
              setState(
                  () => _currentSubtitleStyleMenu = _SubtitleStyleMenu.main);
            },
          ),
        ],
      );
    }
    // Build the specific style submenu based on current selection
    Widget buildSubmenu() {
      switch (_currentSubtitleStyleMenu) {
        case _SubtitleStyleMenu.size:
          return Column(
            children: [
              _buildSubMenuHeader('Font Size',
                  onBack: () => setState(() =>
                      _currentSubtitleStyleMenu = _SubtitleStyleMenu.main)),
              ...sizes.entries.map((e) => _buildStyleOption(
                    e.key,
                    selected: (style.fontSize - e.value).abs() < 0.1,
                    onTap: () async {
                      await mediaService.setSubtitleFontSize(e.value);
                      setState(() {});
                    },
                  )),
            ],
          );
        case _SubtitleStyleMenu.weight:
          return Column(
            children: [
              _buildSubMenuHeader('Font Weight',
                  onBack: () => setState(() =>
                      _currentSubtitleStyleMenu = _SubtitleStyleMenu.main)),
              ...weights.entries.map((e) => _buildStyleOption(
                    e.key,
                    selected: style.fontWeight == e.value,
                    onTap: () async {
                      await mediaService.setSubtitleFontWeight(e.value, e.key);
                      setState(() {});
                    },
                  )),
            ],
          );
        case _SubtitleStyleMenu.opacity:
          return Column(
            children: [
              _buildSubMenuHeader('Background Opacity',
                  onBack: () => setState(() =>
                      _currentSubtitleStyleMenu = _SubtitleStyleMenu.main)),
              ...opacities.entries.map((e) => _buildStyleOption(
                    e.key,
                    selected: (style.backgroundOpacity - e.value).abs() < 0.01,
                    onTap: () async {
                      await mediaService.setSubtitleBackgroundOpacity(e.value);
                      setState(() {});
                    },
                  )),
            ],
          );
        case _SubtitleStyleMenu.color:
          return Column(
            children: [
              _buildSubMenuHeader('Text Color',
                  onBack: () => setState(() =>
                      _currentSubtitleStyleMenu = _SubtitleStyleMenu.main)),
              ...colors.entries.map((e) => _buildStyleOption(
                    e.key,
                    selected: style.color == e.value,
                    onTap: () async {
                      await mediaService.setSubtitleColor(e.value);
                      setState(() {});
                    },
                    trailing: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: e.value,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Colors.white24),
                      ),
                    ),
                  )),
            ],
          );
        case _SubtitleStyleMenu.main:
          return const SizedBox.shrink();
      }
    }

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSubmenu(),
        ],
      ),
    );
  }

  Widget _buildSubtitlesStyleMenuWithBack(VoidCallback onBack,
      {StateSetter? setModalState}) {
    final sizes = <String, double>{
      'Small (18px)': 18,
      'Medium (24px)': 24,
      'Large (36px)': 36,
      'Extra Large (42px)': 42,
    };
    final weights = <String, FontWeight>{
      'Extra Light': FontWeight.w200,
      'Light': FontWeight.w300,
      'Medium': FontWeight.w500,
      'Semi Bold': FontWeight.w600,
      'Bold': FontWeight.w700,
    };
    final opacities = <String, double>{
      '0%': 0.0,
      '25%': 0.25,
      '50%': 0.5,
      '75%': 0.75,
      '100%': 1.0,
    };
    final colors = <String, Color>{
      'White': Colors.white,
      'Yellow': Colors.yellow,
      'Cyan': Colors.cyanAccent,
      'Green': Colors.greenAccent,
      'Magenta': Colors.pinkAccent,
      'Red': Colors.redAccent,
      'Black': Colors.black,
    };
    final style = mediaService.currentSubtitleStyle;
    // Show the main style menu
    if (_currentSubtitleStyleMenu == _SubtitleStyleMenu.main) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSubMenuHeader('Captions Style', onBack: onBack),
          _buildStyleOption(
            'Font Size',
            icon: Icons.text_fields,
            onTap: () {
              if (setModalState != null) {
                setModalState(
                    () => _currentSubtitleStyleMenu = _SubtitleStyleMenu.size);
              } else {
                setState(
                    () => _currentSubtitleStyleMenu = _SubtitleStyleMenu.size);
              }
            },
            trailing: Text(
              '${style.fontSize.toInt()}px',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          _buildStyleOption(
            'Font Weight',
            icon: Icons.line_weight,
            onTap: () {
              if (setModalState != null) {
                setModalState(() =>
                    _currentSubtitleStyleMenu = _SubtitleStyleMenu.weight);
              } else {
                setState(() =>
                    _currentSubtitleStyleMenu = _SubtitleStyleMenu.weight);
              }
            },
            trailing: Text(
              style.fontWeight.toString().split('.').last,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          _buildStyleOption(
            'Background Opacity',
            icon: Icons.opacity,
            onTap: () {
              if (setModalState != null) {
                setModalState(() {
                  _currentSubtitleStyleMenu = _SubtitleStyleMenu.opacity;
                });
              } else {
                setState(() =>
                    _currentSubtitleStyleMenu = _SubtitleStyleMenu.opacity);
              }
            },
            trailing: Text(
              '${(style.backgroundOpacity * 100).toInt()}%',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          _buildStyleOption(
            'Text Color',
            icon: Icons.color_lens,
            onTap: () {
              if (setModalState != null) {
                setModalState(() {
                  _currentSubtitleStyleMenu = _SubtitleStyleMenu.color;
                });
              } else {
                setState(
                    () => _currentSubtitleStyleMenu = _SubtitleStyleMenu.color);
              }
            },
            trailing: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: style.color,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: Colors.white24),
              ),
            ),
          ),
          const Divider(color: Colors.white12, height: 8),
          _buildStyleOption(
            'Reset to Default',
            icon: Icons.restart_alt,
            onTap: () async {
              await _resetToDefaultStyle();
              if (setModalState != null) {
                setModalState(() {});
              }
            },
          ),
        ],
      );
    }
    // Build the specific style submenu based on current selection
    Widget buildSubmenu() {
      void goBackToMain() {
        if (setModalState != null) {
          setModalState(
              () => _currentSubtitleStyleMenu = _SubtitleStyleMenu.main);
        } else {
          setState(() => _currentSubtitleStyleMenu = _SubtitleStyleMenu.main);
        }
      }

      switch (_currentSubtitleStyleMenu) {
        case _SubtitleStyleMenu.size:
          return Column(
            children: [
              _buildSubMenuHeader('Font Size', onBack: goBackToMain),
              ...sizes.entries.map((e) => _buildStyleOption(
                    e.key,
                    selected: (style.fontSize - e.value).abs() < 0.1,
                    onTap: () async {
                      await mediaService.setSubtitleFontSize(e.value);
                      if (setModalState != null) {
                        setModalState(() {});
                      } else {
                        setState(() {});
                      }
                    },
                  )),
            ],
          );
        case _SubtitleStyleMenu.weight:
          return Column(
            children: [
              _buildSubMenuHeader('Font Weight', onBack: goBackToMain),
              ...weights.entries.map((e) => _buildStyleOption(
                    e.key,
                    selected: style.fontWeight == e.value,
                    onTap: () async {
                      await mediaService.setSubtitleFontWeight(e.value, e.key);
                      if (setModalState != null) {
                        setModalState(() {});
                      } else {
                        setState(() {});
                      }
                    },
                  )),
            ],
          );
        case _SubtitleStyleMenu.opacity:
          return Column(
            children: [
              _buildSubMenuHeader('Background Opacity', onBack: goBackToMain),
              ...opacities.entries.map((e) => _buildStyleOption(
                    e.key,
                    selected: (style.backgroundOpacity - e.value).abs() < 0.01,
                    onTap: () async {
                      await mediaService.setSubtitleBackgroundOpacity(e.value);
                      if (setModalState != null) {
                        setModalState(() {});
                      } else {
                        setState(() {});
                      }
                    },
                  )),
            ],
          );
        case _SubtitleStyleMenu.color:
          return Column(
            children: [
              _buildSubMenuHeader('Text Color', onBack: goBackToMain),
              ...colors.entries.map((e) => _buildStyleOption(
                    e.key,
                    selected: style.color == e.value,
                    onTap: () async {
                      await mediaService.setSubtitleColor(e.value);
                      if (setModalState != null) {
                        setModalState(() {});
                      } else {
                        setState(() {});
                      }
                    },
                    trailing: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: e.value,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Colors.white24),
                      ),
                    ),
                  )),
            ],
          );
        case _SubtitleStyleMenu.main:
          return const SizedBox.shrink();
      }
    }

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSubmenu(),
        ],
      ),
    );
  }

  Widget _buildStyleOption(String label,
      {bool? selected,
      required VoidCallback onTap,
      Widget? trailing,
      IconData? icon}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (selected != null || icon != null)
                Icon(
                  icon ??
                      (selected!
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off),
                  color: icon != null
                      ? Colors.white
                      : (selected!
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white54),
                  size: 16,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected == null
                        ? Colors.white
                        : selected
                            ? Colors.white
                            : Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubMenuHeader(
    String title, {
    VoidCallback? onBack,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onBack ??
            () => setState(() => _currentSettingsMenu = _SettingsMenu.main),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
          child: Row(
            children: [
              const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white, size: 15),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsMenuItem({
    required IconData icon,
    required String title,
    String? value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              if (value != null)
                Text(
                  value,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_ios,
                  color: Colors.white70, size: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedOption(double speed, {StateSetter? setModalState}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          mediaService.setSpeed(speed);
          if (setModalState != null) {
            setModalState(() => _playbackSpeed = speed);
          } else {
            setState(() => _playbackSpeed = speed);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                _playbackSpeed == speed
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: _playbackSpeed == speed
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white54,
                size: 16,
              ),
              const SizedBox(width: 12),
              Text(
                '${speed}x',
                style: TextStyle(
                  color:
                      _playbackSpeed == speed ? Colors.white : Colors.white70,
                  fontSize: 14,
                ),
              ),
              if (speed == 1.0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Text(
                    'Default',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQualityOption(VideoQuality quality,
      {StateSetter? setModalState}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          mediaService.changeQuality(quality);
          if (setModalState != null) {
            setModalState(() {});
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                quality == mediaService.currentQuality
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: quality == mediaService.currentQuality
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white54,
                size: 16,
              ),
              const SizedBox(width: 12),
              Text(
                quality.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitleOption(String label,
      {bool isSelected = false,
      bool isProcessing = false,
      bool isGenerated = false,
      VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white54,
                size: 16,
              ),
              const SizedBox(width: 12),
              if (isProcessing) ...[
                Icon(
                  Icons.hourglass_top,
                  color: Colors.white54,
                  size: 16,
                ),
                const SizedBox(width: 6),
              ] else if (isGenerated) ...[
                Icon(
                  Icons.bolt,
                  color: Colors.yellow,
                  size: 16,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback onPressed,
      {double size = 24}) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: size),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: onPressed,
    );
  }

  Widget _buildVolumeButtonAndSlider() {
    return MouseRegion(
      onEnter: (_) => setState(() => _showVolumeSlider = true),
      onExit: (_) => setState(() => _showVolumeSlider = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              _volume == 0
                  ? Icons.volume_off_rounded
                  : _volume <= 0.4
                      ? Icons.volume_mute_rounded
                      : _volume >= 0.65
                          ? Icons.volume_up_rounded
                          : Icons.volume_down_rounded,
              key: ValueKey<double>(_volume),
              size: 24,
              color: Colors.white,
            ),
            onPressed: () {
              if (_volume > 0) {
                setState(() => _volume = 0);
                mediaService.setVolume(0);
              } else {
                setState(() => _volume = 1);
                mediaService.setVolume(1);
              }
            },
          ),
          AnimatedOpacity(
            opacity: _showVolumeSlider ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _showVolumeSlider ? 60 : 0,
              curve: Curves.easeInOut,
              // Add the LayoutBuilder here
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Only build the slider if the width is usable
                  if (constraints.maxWidth > 2) {
                    return SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 2,
                        thumbShape: SliderComponentShape.noThumb,
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 0),
                      ),
                      child: Slider(
                        value: _volume.clamp(0.0, 1.0),
                        onChanged: (value) {
                          setState(() => _volume = value);
                          _volumeDragging = true;
                          mediaService.setVolume(value);
                        },
                        onChangeEnd: (value) {
                          _volumeDragging = false;
                          mediaService.setVolume(value);
                          setState(() => _volume = value);
                        },
                      ),
                    );
                  } else {
                    // Otherwise, build an empty box.
                    return const SizedBox.shrink();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }

  void _toggleSettings() {
    final isMobile = !widget.isDesktop;
    if (isMobile) {
      // Show bottom sheet on mobile
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => _buildMobileSettingsSheet(),
      ).then((_) {
        // Reset to main menu when closing
        setState(() {
          _currentSettingsMenu = _SettingsMenu.main;
        });
      });
    } else {
      // Show overlay panel on desktop
      setState(() {
        _showSettings = !_showSettings;
        if (!_showSettings) {
          // If user manually closes settings, don't restore them on next hover.
          _settingsWereOpen = false;
          // Reset to main menu when closing
          _currentSettingsMenu = _SettingsMenu.main;
        }
      });
    }
  }

  void _toggleFullscreen() {
    if (widget.isFullscreen) {
      // Exit fullscreen by popping the overlay route
      exitFullscreen(context);
    } else {
      // Enter fullscreen by pushing an overlay route
      enterFullscreen(
        context,
        video: widget.video!,
        isDesktop: widget.isDesktop,
        thumbnailSprite: widget.thumbnailSprite,
        pipAvailable: widget.pipAvailable,
      );
    }
  }
}
