import 'package:better_player_plus/better_player_plus.dart';
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
  });
  @override
  ConsumerState<MediaPlayerWidget> createState() => _MediaPlayerWidgetState();
}
class _MediaPlayerWidgetState extends ConsumerState<MediaPlayerWidget> {
  bool subtitlesEnabled = false;
  late MediaPlayerService _mediaService;
  bool _isInitialized = false;
  dynamic _controller;
  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }
  Future<void> _initializePlayer() async {
    print('Initializing player...');
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
    );
    print('Player initialized');
    print('Initial state: ${widget.initialState}');
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
    print('Building media content...');
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
        //         if (widget.textTracks?.isNotEmpty == true)
        //           StatefulBuilder(
        //             builder: (context, setState) {
        //               return MaterialDesktopCustomButton(
        //                 icon: Icon(
        //                   subtitlesEnabled
        //                       ? Icons.closed_caption
        //                       : Icons.closed_caption_off,
        //                   color: Colors.white,
        //                 ),
        //                 onPressed: () async {
        //                   final subtitles =
        //                       await _mediaService.toggleSubtitles();
        //                   setState(() {
        //                     subtitlesEnabled = subtitles;
        //                   });
        //                 },
        //               );
        //             },
        //           ),
        //         MaterialDesktopCustomButton(
        //           icon: const Icon(Icons.picture_in_picture),
        //           onPressed: () {
        //             _mediaService.changeState(MediaPlayerState.pip);
        //             if (!mounted) return;
        //             widget.contextBuild.go('/pip', extra: {
        //               'controller': _mediaService.videoController,
        //               'postId': widget.postId,
        //               'live': _mediaService.currentLive,
        //             });
        //           },
        //         ),
        Widget videoWidget;
        print('check');
        if (_controller is VideoController) {
          print('MediaKit');
          videoWidget = Video(
            key: ValueKey('v-${widget.postId ?? widget.mediaUrl}'),
            controller: videoController,
            controls: NoVideoControls,
            pauseUponEnteringBackgroundMode: false,
          );
        } else if (_controller is BetterPlayerController) {
          print('BetterPlayer');
          videoWidget = BetterPlayer(controller: _mediaService.betterPlayer);
        } else {
          print('Unknown Player Type');
          videoWidget = const SizedBox.shrink();
        }
        return CustomPlayer(
          key: ValueKey(widget.postId ?? widget.mediaUrl),
          isDesktop: true,
          video: videoWidget,
          thumbnailSprite: widget.timelineSprite,
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
  @override
  void dispose() {
    super.dispose();
  }
}