import 'dart:io';
import 'package:logging/logging.dart';

import 'package:floaty/features/api/models/definitions.dart';
import 'package:floaty/features/player/components/custom_player/custom_player.dart';
import 'package:floaty/features/player/models/seekbar_chapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../controllers/media_player_service.dart';
import '../models/video_quality.dart';
import 'package:floaty/features/player/components/audio_controls.dart';
import 'package:floaty/features/player/theme/audio_controls_theme.dart';

class MediaPlayerWidget extends ConsumerStatefulWidget {
  final String whitelabelName;
  final String mediaUrl;
  final MediaType mediaType;
  final bool live;
  final dynamic attachment;
  final List<VideoQuality>? qualities;
  final int startFrom;
  final BuildContext contextBuild;
  final String? title;
  final String? artist;
  final String? artistImage;
  final String? postId;
  final String? artworkUrl;
  final ImageModel? timelineSprite;
  final bool discoverable;
  final MediaPlayerState initialState;
  final List<Map<String, dynamic>>? textTracks;
  final List<SeekbarChapter>? chapters;
  final ContentPostV3Response? offlinePost;
  final String? offlineAttachmentId;
  final String? offlineFilePath;
  const MediaPlayerWidget({
    super.key,
    required this.whitelabelName,
    required this.mediaUrl,
    required this.mediaType,
    required this.attachment,
    required this.contextBuild,
    this.qualities,
    this.initialState = MediaPlayerState.main,
    required this.startFrom,
    required this.title,
    required this.artist,
    required this.artistImage,
    required this.postId,
    required this.artworkUrl,
    this.timelineSprite,
    required this.discoverable,
    required this.live,
    this.textTracks,
    this.chapters,
    this.offlinePost,
    this.offlineAttachmentId,
    this.offlineFilePath,
  });
  @override
  ConsumerState<MediaPlayerWidget> createState() => _MediaPlayerWidgetState();
}

class _MediaPlayerWidgetState extends ConsumerState<MediaPlayerWidget>
    with WidgetsBindingObserver {
  final Logger _log = Logger('MediaPlayerWidget');
  bool subtitlesEnabled = false;
  late MediaPlayerService _mediaService;
  bool _isInitialized = false;
  dynamic _controller;
  bool init = false;
  bool pipAvailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (init == false) {
      _initializePlayer();
      init = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    _log.info('Initializing player...');
    _log.info(
        'MediaPlayerWidget offline params: offlinePost=${widget.offlinePost != null}, offlineAttachmentId=${widget.offlineAttachmentId}, offlineFilePath=${widget.offlineFilePath}');
    _log.info('MediaPlayerWidget URL: ${widget.mediaUrl}');
    _log.info(
        'MediaPlayerWidget isOffline check: ${widget.mediaUrl.startsWith('file://')}');
    subtitlesEnabled =
        ref.read(mediaPlayerServiceProvider.notifier).subtitlesEnabled;
    _mediaService = ref.read(mediaPlayerServiceProvider.notifier);
    _controller = await _mediaService.setSource(
      widget.whitelabelName,
      widget.mediaUrl,
      widget.mediaType,
      widget.live,
      attachment: widget.attachment,
      qualities: widget.qualities,
      start: Duration(seconds: widget.startFrom),
      title: widget.title,
      artist: widget.artist,
      artistImage: widget.artistImage,
      postId: widget.postId,
      thumbnailUrl: widget.artworkUrl,
      discoverable: widget.discoverable,
      textTracks: widget.textTracks,
      timelineSprite: widget.timelineSprite,
      chapters: widget.chapters,
      isOffline: widget.mediaUrl.startsWith('file://'),
      offlinePost: widget.offlinePost,
      offlineAttachmentId: widget.offlineAttachmentId,
      offlineFilePath: widget.offlineFilePath,
    );

    pipAvailable = await _mediaService.isPipAvailable();

    _log.info('Player initialized');
    _log.info('Initial state: ${widget.initialState}');
    await _mediaService.changeState(widget.initialState);
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
      if (widget.mediaType != MediaType.image) {
        _mediaService.play();
      }
    }
  }

  Widget _buildMediaContent() {
    _log.fine('Building media content...');
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    switch (widget.mediaType) {
      case MediaType.video:
        final videoController = _controller;
        if (videoController == null) {
          return const Center(
              child: CircularProgressIndicator(
            color: Colors.white,
          ));
        }
        Widget videoWidget;
        _log.fine('Checking controller type');
        if (_controller is VideoController) {
          _log.fine('Using MediaKit player');
          videoWidget = Video(
            key: ValueKey('v-${widget.postId ?? widget.mediaUrl}'),
            controller: videoController,
            controls: NoVideoControls,
            pauseUponEnteringBackgroundMode: false,
          );
          // } else if (_controller is BetterPlayerController) {
          //   print('BetterPlayer');
          //   videoWidget = BetterPlayer(
          //     key: _mediaService.betterPlayerGlobalKey,
          //     controller: _mediaService.betterPlayer,
          //   );
        } else {
          _log.warning('Unknown Player Type');
          videoWidget = const SizedBox.shrink();
        }

        return CustomPlayer(
          key: ValueKey(widget.postId ?? widget.mediaUrl),
          isDesktop:
              (Platform.isWindows || Platform.isLinux || Platform.isMacOS),
          video: videoWidget,
          thumbnailSprite: widget.timelineSprite,
          pipAvailable: pipAvailable,
        );
      case MediaType.audio:
        final theme = AudioControlsThemeData(
          modifyVolumeOnScroll: false,
          hideMouseOnControlsRemoval: false,
          playAndPauseOnTap: true,
          bottomButtonBarMargin:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          seekBarMargin: const EdgeInsets.symmetric(horizontal: 16.0),
          seekBarHeight: 4.0,
          seekBarHoverHeight: 4.0,
          seekBarContainerHeight: 40.0,
          seekBarColor: const Color(0x3DFFFFFF),
          seekBarThumbColor: Colors.white,
          seekBarPositionColor: colorScheme.primary,
          seekBarBufferColor: const Color(0x3DFFFFFF),
          seekBarThumbSize: 12.0,
          buttonBarHeight: 48.0,
          buttonBarButtonSize: 32.0,
        );
        return Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.black,
          ),
          child: AudioControls(
            theme: theme,
          ),
        );
      case MediaType.image:
        return Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: NetworkImage(widget.mediaUrl),
              fit: BoxFit.fitHeight,
            ),
          ),
        );
    }
  }

  Widget _buildMediaPlayer() {
    final playerState = ref.watch(mediaPlayerServiceProvider);
    switch (playerState) {
      case MediaPlayerState.none:
        return _buildMainPlayer();
      case MediaPlayerState.main:
        return _buildMainPlayer();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildMainPlayer() {
    return Scaffold(
      body: Center(
        child: _buildMediaContent(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(
          child: CircularProgressIndicator(
        color: Colors.white,
      ));
    }
    return _buildMediaPlayer();
  }
}
