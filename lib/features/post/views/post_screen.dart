import 'dart:io';
import 'package:floaty/features/post/components/blog_post_card.dart';
import 'package:floaty/features/post/components/comment_holder.dart';
import 'package:floaty/features/post/components/expandable_description.dart';
import 'package:floaty/features/post/components/state_card.dart';
import 'package:floaty/shared/views/error_screen.dart';
import 'package:floaty/whitelabels.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:floaty/features/post/repositories/post_provider.dart';
import 'package:floaty/features/router/views/root_layout.dart';
import 'package:floaty/features/api/repositories/fpapi.dart';
import 'package:floaty/features/api/models/definitions.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:fwfh_url_launcher/fwfh_url_launcher.dart';
import 'dart:math';
import 'package:floaty/features/player/components/media_player_widget.dart';
import 'package:floaty/features/player/controllers/media_player_service.dart';
import 'package:floaty/features/player/models/video_quality.dart';
import 'dart:convert';
import 'package:floaty/settings.dart';
import 'package:floaty/features/download/components/fp_download_dialog.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:package_info_plus/package_info_plus.dart';

enum ScreenLayout { small, medium, wide }

class VideoDetailPage extends ConsumerStatefulWidget {
  const VideoDetailPage({
    super.key,
    required this.postId,
    this.t,
    this.a,
    this.isOffline = false,
    this.offlinePost,
    this.offlineAttachmentId,
    this.offlineFilePath,
  });
  final String postId;
  final int? t;
  final String? a;
  final bool isOffline;
  final ContentPostV3Response? offlinePost;
  final String? offlineAttachmentId;
  final String? offlineFilePath;
  @override
  ConsumerState<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends ConsumerState<VideoDetailPage> {
  late String postId;
  late MediaPlayerService _mediaService;
  final _commentController = TextEditingController();
  final _focusNode = FocusNode();
  final _attachmentScrollController = ScrollController();
  late Future<Widget> _mediaContentFuture;
  int _currentLength = 0;
  final int _pageSize = 20;
  String fetchafter = '0';
  String sortBy = 'createdAt';
  String sortOrder = 'DESC';
  String? _selectedAttachmentId;
  dynamic selectedAttachment;
  bool text = false;
  bool isWan = false;
  String letsBeHonestItsLateTime = '';
  bool hundredpercentlate = false;
  String preShowRange = '';
  String preShowDuration = '';
  String mainShowRange = '';
  String mainShowDuration = '';
  String latenessString = '';
  String? mediaUrl;
  MediaType selectedMediaType = MediaType.video; // Default
  late MediaPlayerService mediaService;
  late MediaPlayerState mediaState;
  late List<PopupMenuEntry<String>> menuItems;
  final List<CommentModel> _comments = [];
  bool _isLoadingComments = false;
  bool _hasMoreComments = true;
  String userAgent = 'FloatyClient/error';
  PackageInfo? packageInfo;
  @override
  void initState() {
    super.initState();
    initUserAgent();
    postId = widget.postId;
    _mediaContentFuture = Future(() async {
      // If offline mode, skip waiting for provider to load
      if (widget.isOffline) {
        debugPrint('[FP] Loading offline video');
        return _buildMediaContent();
      }

      // Wait for post to be loaded
      if (postId.isEmpty) {
        postId = mediaService.currentPostId ?? '';
      }
      while (ref
          .read(postProvider(
              postId.isEmpty ? mediaService.currentPostId ?? '' : postId))
          .isLoading) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _buildMediaContent();
    });
    _commentController.addListener(_updateCharCount);

    // Don't load comments in offline mode
    if (!widget.isOffline) {
      _loadComments();
    }
  }

  Future<void> initUserAgent() async {
    packageInfo = await PackageInfo.fromPlatform();
    const flavor =
        String.fromEnvironment('FLUTTER_FLAVOR', defaultValue: 'release');
    userAgent =
        'FloatyClient/${packageInfo?.version}+${packageInfo?.buildNumber}-$flavor';
  }

  //whenplane intergration
  //100% not converted from the browser extension
  String? extractShowDate(String title) {
    final titleRegex = RegExp(
        r" - WAN Show ((January|February|March|April|May|June|July|August|September|October|November|December) \d{1,2}, \d{4})");
    final match = titleRegex.firstMatch(title);
    if (match != null) {
      String dateString =
          match.group(1)!; // Extracted date as "February 14, 2025"
      // Parse into DateTime object
      DateTime parsedDate = DateFormat("MMMM d, yyyy").parse(dateString);
      // Convert to YYYY/MM/DD format
      return DateFormat("yyyy/MM/dd").format(parsedDate);
    }
    return null;
  }

  String formatDate(String rawDate) {
    final date = DateTime.parse(rawDate);
    return "${date.year}/${addZero(date.month)}/${addZero(date.day)}";
  }

  String addZero(int n) => n > 9 ? "$n" : "0$n";
  String convertTimeFormat(String date1, String date2, bool length) {
    DateTime start = DateTime.parse(date1).toUtc();
    DateTime end = DateTime.parse(date2).toUtc();
    if (length) {
      return formatDuration(end.difference(start));
    } else {
      return "${formatTime(start)} - ${formatTime(end)}";
    }
  }

  String formatTime(DateTime date) {
    return "${addZero(date.hour)}:${addZero(date.minute)}";
  }

  String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  // Parse timestamp from HH:MM:SS, MM:SS, or seconds
  int _parseTimestamp(String input) {
    // Try to parse as HH:MM:SS or MM:SS
    final parts = input.split(':');
    if (parts.length >= 2) {
      try {
        if (parts.length == 3) {
          // HH:MM:SS format
          final hours = int.parse(parts[0]);
          final minutes = int.parse(parts[1]);
          final seconds = double.parse(parts[2]).toInt();
          return hours * 3600 + minutes * 60 + seconds;
        } else if (parts.length == 2) {
          // MM:SS format
          final minutes = int.parse(parts[0]);
          final seconds = double.parse(parts[1]).toInt();
          return minutes * 60 + seconds;
        }
      } catch (e) {
        // If parsing fails, try parsing as raw seconds
      }
    }
    // Try parsing as raw seconds
    return int.tryParse(input) ?? 0;
  }

  // Format seconds into HH:MM:SS or MM:SS for display
  String _formatTimestampForInput(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${secs.toString().padLeft(2, '0')}';
    }
  }

  @override
  void dispose() {
    Future.microtask(() async {
      if (mediaService.playing &&
          mediaService.mediastate == MediaPlayerState.main) {
        mediaService.changeState(MediaPlayerState.mini);
      }
    });
    Future.microtask(() async {
      if (selectedMediaType == MediaType.video ||
          selectedMediaType == MediaType.audio) {
        fpApiRequests.progress(
          (await whitelabels.getSelectedWhitelabel()).friendlyName,
          _selectedAttachmentId ?? '',
          _mediaService.currentPosition.inSeconds,
          selectedMediaType.name,
          isOffline: _mediaService.isOffline,
        );
      }
    });
    _commentController.removeListener(_updateCharCount);
    _commentController.dispose();
    _focusNode.dispose();
    _attachmentScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(VideoDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (postId != widget.postId) {
      postId = widget.postId;
      setState(() {
        _mediaContentFuture = Future(() async {
          return _buildMediaContent();
        });
      });
    }
  }

  void _updateCharCount() {
    setState(() {
      _currentLength = _commentController.text.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    _mediaService = ref.watch(mediaPlayerServiceProvider.notifier);

    // In offline mode, skip provider and use offline data
    final dynamic postState = widget.isOffline
        ? _PostStateOffline(widget.offlinePost!)
        : ref.watch(postProvider(widget.postId));

    menuItems = ref.watch(menuItemsProvider);
    if (!Platform.isAndroid && !Platform.isIOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // while (!postState.isLoading) {
        //   if (postState.post?.creator?.title?.toLowerCase() == 'eccsquad' &&
        //           await settings.getBool('discord_rpc') == false &&
        //           await settings.getBool('eccsquadwarningseen') == false ||
        //       postState.post?.creator?.title?.toLowerCase() == 'ecc squad' &&
        //           await settings.getBool('discord_rpc') == false &&
        //           await settings.getBool('eccsquadwarningseen') == false) {
        //     context.pushReplacement('/ecc-warning/${widget.postId}');
        //   } else if (postState.post?.creator?.discoverable == false) {
        //     context.pushReplacement('/ecc-warning/${widget.postId}',
        //         extra: 'discoverable');
        //   }
        //   break;
        // }
      });
    }

    // Show error screen if there's an error and no post data (skip in offline mode)
    if (!widget.isOffline && postState.hasError && postState.post == null) {
      return Scaffold(
        body: postState.exception != null
            ? ErrorScreen.fromException(
                postState.exception!,
                onRetry: () => ref
                    .read(postProvider(widget.postId).notifier)
                    .retry(widget.postId),
              )
            : ErrorScreen(
                message: postState.error,
                subtext: 'Failed to load post',
                onRetry: () => ref
                    .read(postProvider(widget.postId).notifier)
                    .retry(widget.postId),
              ),
      );
    }

    return postState.isLoading
        ? const Center(child: CircularProgressIndicator())
        : Scaffold(
            body: RefreshIndicator(
              onRefresh: () async {
                _loadComments();
              },
              child: SingleChildScrollView(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 1000;
                    final isMedium = constraints.maxWidth > 700 &&
                        constraints.maxWidth <= 1000;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: text == false ? double.infinity : 0,
                          height: text == false
                              ? min(
                                  constraints.maxWidth * 9 / 16,
                                  MediaQuery.of(context).size.height - 250,
                                )
                              : 0,
                          decoration: BoxDecoration(
                            color: Colors.black,
                          ),
                          child: FutureBuilder<Widget>(
                            future: _mediaContentFuture,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                    child: CircularProgressIndicator(
                                  color: Colors.white,
                                ));
                              } else if (snapshot.hasError) {
                                return Center(
                                    child: Text('Error: ${snapshot.error}'));
                              } else {
                                return snapshot.data!;
                              }
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: isWide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: _buildMainContent(
                                          constraints, theme, colorScheme),
                                    ),
                                    const SizedBox(width: 24),
                                    _buildRecommendedSection(constraints,
                                        layout: ScreenLayout.wide),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildMainContent(
                                        constraints, theme, colorScheme),
                                    _buildRecommendedSection(
                                      constraints,
                                      layout: isMedium
                                          ? ScreenLayout.medium
                                          : ScreenLayout.small,
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
  }

  Future<Widget> _buildMediaContent() async {
    mediaService = ref.read(mediaPlayerServiceProvider.notifier);
    mediaState = ref.read(mediaPlayerServiceProvider);
    List<Map<String, dynamic>> textTrack = [];
    try {
      // Handle offline mode
      if (widget.isOffline &&
          widget.offlinePost != null &&
          widget.offlineFilePath != null) {
        debugPrint('[FP] Building offline media player');

        final post = widget.offlinePost!;
        _selectedAttachmentId =
            widget.offlineAttachmentId ?? post.attachmentOrder.firstOrNull;

        // Find the attachment
        for (final video in post.videoAttachments) {
          if (video.id == _selectedAttachmentId) {
            selectedAttachment = video;
            selectedMediaType = MediaType.video;
            break;
          }
        }
        if (selectedAttachment == null) {
          for (final audio in post.audioAttachments) {
            if (audio.id == _selectedAttachmentId) {
              selectedAttachment = audio;
              selectedMediaType = MediaType.audio;
              break;
            }
          }
        }

        // Get saved offline progress for this attachment
        int savedProgress = 0;
        if (_selectedAttachmentId != null &&
            _selectedAttachmentId!.isNotEmpty) {
          savedProgress =
              await fpApiRequests.getOfflineProgress(_selectedAttachmentId!);
        }

        // Use local file path instead of streaming URL
        return MediaPlayerWidget(
          whitelabelName:
              (await whitelabels.getSelectedWhitelabel()).friendlyName,
          contextBuild: context.mounted ? context : context,
          mediaUrl: 'file://${widget.offlineFilePath}',
          discoverable: post.creator?.discoverable ?? false,
          live: false,
          mediaType: selectedMediaType,
          attachment: selectedAttachment,
          qualities: null, // No quality switching for offline videos
          initialState: MediaPlayerState.main,
          startFrom: widget.t ?? savedProgress,
          textTracks: null, // No text tracks for offline videos
          title: post.title ?? 'Unknown Title',
          artist: post.channel?.title ?? 'Unknown Creator',
          artistImage: post.channel?.icon?.path ?? '',
          postId: widget.postId,
          artworkUrl: post.thumbnail?.path ?? '',
          timelineSprite: null, // No timeline sprite for offline videos
          offlinePost: widget.offlinePost,
          offlineAttachmentId: widget.offlineAttachmentId,
          offlineFilePath: widget.offlineFilePath,
        );
      }

      // Check if the media service is already playing this exact post
      // This handles returning from PiP/mini player without re-initializing
      final hasActivePlayer = mediaService.videoController != null;
      //||mediaService.betterPlayerController != null;
      if (mediaService.currentPostId == widget.postId && hasActivePlayer) {
        // Already playing this post - return existing player without re-initialization
        final postState = ref.watch(postProvider(widget.postId));
        final post = postState.post;

        // Determine the selected attachment type from what's currently playing
        _selectedAttachmentId = mediaService.currentAttachmentId;

        // Find the attachment type
        for (final video in post?.videoAttachments ?? []) {
          if (video.id == _selectedAttachmentId) {
            selectedAttachment = video;
            selectedMediaType = MediaType.video;
            break;
          }
        }
        if (selectedAttachment == null) {
          for (final audio in post?.audioAttachments ?? []) {
            if (audio.id == _selectedAttachmentId) {
              selectedAttachment = audio;
              selectedMediaType = MediaType.audio;
              break;
            }
          }
        }
        if (selectedAttachment == null) {
          for (final picture in post?.pictureAttachments ?? []) {
            if (picture.id == _selectedAttachmentId) {
              selectedAttachment = picture;
              selectedMediaType = MediaType.image;
              break;
            }
          }
        }

        // Return MediaPlayerWidget with same parameters - it will detect same URL and skip init
        debugPrint(
            'POST_SCREEN: Reusing existing player for post ${widget.postId}');
        debugPrint(
            'POST_SCREEN: mediaService.isOffline=${mediaService.isOffline}');
        debugPrint(
            'POST_SCREEN: mediaService.offlinePost=${mediaService.offlinePost != null}');
        debugPrint(
            'POST_SCREEN: mediaService.offlineAttachmentId=${mediaService.offlineAttachmentId}');
        debugPrint(
            'POST_SCREEN: mediaService.offlineFilePath=${mediaService.offlineFilePath}');
        debugPrint(
            'POST_SCREEN: mediaService.currentMediaUrl=${mediaService.currentMediaUrl}');
        return MediaPlayerWidget(
          whitelabelName:
              (await whitelabels.getSelectedWhitelabel()).friendlyName,
          contextBuild: context.mounted ? context : context,
          mediaUrl: mediaService.currentMediaUrl ?? '',
          discoverable: post?.creator?.discoverable ?? false,
          live: false,
          mediaType: selectedMediaType,
          attachment: selectedAttachment,
          qualities: mediaService.availableQualities,
          initialState: MediaPlayerState.main,
          startFrom: mediaService.currentPosition.inSeconds,
          textTracks: mediaService.textTracks,
          title: mediaService.currentTitle ?? 'Unknown Title',
          artist: mediaService.currentArtist ?? 'Unknown Creator',
          artistImage: mediaService.currentArtistImage ?? '',
          postId: widget.postId,
          artworkUrl: mediaService.currentThumbnailUrl ?? '',
          timelineSprite: mediaService.currentTimelineSprite,
          offlinePost: mediaService.offlinePost,
          offlineAttachmentId: mediaService.offlineAttachmentId,
          offlineFilePath: mediaService.offlineFilePath,
        );
      }

      final postState = ref.watch(postProvider(widget.postId));
      final post = postState.post;
      if (post == null) {
        return const Center(child: CircularProgressIndicator());
      }
      int progress = 0;
      // If no attachments, show no content
      if (post.attachmentOrder.isEmpty) {
        text = true;
        return const SizedBox.shrink();
      }
      // If no attachment found, default to first
      if (widget.a != null) {
        _selectedAttachmentId = widget.a;
      } else {
        _selectedAttachmentId ??= post.attachmentOrder.first;
      }
      // Search through video attachments
      for (final video
          in ref.read(postProvider(widget.postId)).post!.videoAttachments) {
        if (video.id == _selectedAttachmentId) {
          selectedAttachment = video;
          selectedMediaType = MediaType.video;
          break;
        }
      }
      // If not found, search through audio attachments
      if (selectedAttachment == null) {
        for (final audio
            in ref.read(postProvider(widget.postId)).post!.audioAttachments) {
          if (audio.id == _selectedAttachmentId) {
            selectedAttachment = audio;
            selectedMediaType = MediaType.audio;
            break;
          }
        }
      }
      // If not found, search through picture attachments
      if (selectedAttachment == null) {
        for (final picture
            in ref.read(postProvider(widget.postId)).post!.pictureAttachments) {
          if (picture.id == _selectedAttachmentId) {
            selectedAttachment = picture;
            selectedMediaType = MediaType.image;
            break;
          }
        }
      }
      // Determine media URL based on attachment type
      List<VideoQuality>? qualities;
      if (selectedAttachment != null) {
        if (selectedAttachment is VideoAttachmentModel) {
          final deliveryResponse = await fpApiRequests.getDelivery(
              (await whitelabels.getSelectedWhitelabel()).friendlyName,
              'onDemand',
              _selectedAttachmentId!);
          final res = deliveryResponse['body'] as String;
          final decoded = jsonDecode(res);
          qualities = await fetchVideoQualities(decoded, true);
          final prores = await fpApiRequests.getContent(
              (await whitelabels.getSelectedWhitelabel()).friendlyName,
              'video',
              _selectedAttachmentId!);
          final decodedpro = jsonDecode(prores);
          if (decodedpro['progress'] != null) {
            progress = decodedpro['progress'];
          }
          textTrack = (decodedpro['textTracks'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          // Determine the default quality using the Settings class
          String? preferredQuality = await settings.getKey('preferred_quality');
          if (preferredQuality.isNotEmpty) {
            VideoQuality? selectedQuality = qualities.firstWhere(
              (quality) => quality.label == preferredQuality,
              orElse: () => qualities!.first, // Fallback to the first quality
            );
            mediaUrl = selectedQuality.url; // Just use the URL directly
          } else {
            // Check for 1080p quality
            VideoQuality? defaultQuality = qualities.firstWhere(
              (quality) => quality.label == '1080p',
              orElse: () => qualities!
                  .first, // Fallback to the first quality if 1080p doesn't exist
            );
            mediaUrl = defaultQuality.url;
          }
        } else if (selectedAttachment is AudioAttachmentModel) {
          final deliveryResponse = await fpApiRequests.getDelivery(
              (await whitelabels.getSelectedWhitelabel()).friendlyName,
              'onDemand',
              _selectedAttachmentId!);
          final res = deliveryResponse['body'] as String;
          final decoded = jsonDecode(res);
          qualities = await fetchVideoQualities(decoded, false);
          final prores = await fpApiRequests.getContent(
              (await whitelabels.getSelectedWhitelabel()).friendlyName,
              'audio',
              _selectedAttachmentId!);
          final decodedpro = jsonDecode(prores);
          if (decodedpro['progress'] != null) {
            progress = decodedpro['progress'];
            textTrack = (decodedpro['textTracks'] as List?)
                    ?.cast<Map<String, dynamic>>() ??
                [];
          }
          // Determine the default quality using the Settings class
          String? preferredQuality = await settings.getKey('preferred_quality');
          if (preferredQuality.isNotEmpty) {
            VideoQuality? selectedQuality = qualities.firstWhere(
              (quality) => quality.label == preferredQuality,
              orElse: () => qualities!.first, // Fallback to the first quality
            );
            mediaUrl = selectedQuality.url; // Just use the URL directly
          } else {
            // Check for 1080p quality
            VideoQuality? defaultQuality = qualities.firstWhere(
                (quality) => quality.label == '1080p',
                orElse: () => qualities!
                    .first // Fallback to the first quality if 1080p doesn't exist
                );
            mediaUrl = defaultQuality.url;
          }
        } else if (selectedAttachment is PictureAttachmentModel) {
          final res = await fpApiRequests.getContent(
              (await whitelabels.getSelectedWhitelabel()).friendlyName,
              'picture',
              _selectedAttachmentId!);
          final decoded = jsonDecode(res);
          mediaUrl = decoded['imageFiles'][0]['path'];
        }
      }
      // If only one attachment
      return MediaPlayerWidget(
        whitelabelName:
            (await whitelabels.getSelectedWhitelabel()).friendlyName,
        contextBuild: context.mounted ? context : context,
        mediaUrl: mediaUrl!,
        discoverable:
            ref.read(postProvider(widget.postId)).post?.creator?.discoverable ??
                false,
        live: false,
        mediaType: selectedMediaType,
        attachment: selectedAttachment,
        qualities:
            selectedMediaType == MediaType.video && selectedAttachment != null
                ? qualities
                : null,
        initialState: MediaPlayerState.main,
        startFrom: widget.t ?? progress,
        textTracks: textTrack.isEmpty ? null : textTrack,
        title: ref.read(postProvider(widget.postId)).post?.title ??
            'Unknown Title',
        artist: ref.read(postProvider(widget.postId)).post?.channel?.title ??
            'Unknown Creator',
        artistImage:
            ref.read(postProvider(widget.postId)).post?.channel?.icon?.path ??
                '',
        postId: widget.postId,
        artworkUrl:
            ref.read(postProvider(widget.postId)).post!.thumbnail?.path ?? '',
        timelineSprite: post.videoAttachments
            .where((attachment) => attachment.id == _selectedAttachmentId)
            .firstOrNull
            ?.timelineSprite,
      );
    } catch (e) {
      return const Center(
          child: CircularProgressIndicator(
        color: Colors.white,
      ));
    }
  }

  Future<List<VideoQuality>> fetchVideoQualities(
      Map<String, dynamic> deliveryResponse, bool video,
      {bool v2 = false}) async {
    List<VideoQuality> qualities = [];
    if (!v2) {
      // Extract base URL from origins
      String baseUrl = deliveryResponse['groups'][0]['origins'][0]['url'];
      // Access the groups and their variants
      for (var group in deliveryResponse['groups']) {
        for (var variant in group['variants']) {
          // Check if the variant is enabled
          if (variant['enabled']) {
            if (video = true) {
              qualities.add(VideoQuality(
                url:
                    '$baseUrl${variant['url']}', // Concatenate base URL with the variant URL
                label: variant['label'],
              ));
            } else {
              qualities.add(VideoQuality(
                url:
                    '$baseUrl${variant['url']}', // Concatenate base URL with the variant URL
                label: variant['label'],
              ));
            }
          }
        }
      }
    } else {
      // Extract base URL from origins
      String baseUrl = deliveryResponse['cdn'];
      // Access the groups and their variants
      for (var quality in deliveryResponse['resource']['data']
          ['qualityLevels']) {
        final qualityName = quality['name'];
        final qualityParams = deliveryResponse['resource']['data']
            ['qualityLevelParams'][qualityName];
        if (qualityParams != null) {
          final pathParam = qualityParams['2'];
          final token = qualityParams['4'];
          final uri = deliveryResponse['resource']['uri']
              .replaceAll('{qualityLevelParams.2}', pathParam)
              .replaceAll('{qualityLevelParams.4}', token);
          qualities.add(VideoQuality(
            url: '$baseUrl$uri',
            label: quality['label'],
          ));
        }
      }
    }
    return qualities;
  }

  String _getSortDisplayText() {
    if (sortBy == 'createdAt' && sortOrder == 'DESC') {
      return 'newest';
    } else if (sortBy == 'createdAt' && sortOrder == 'ASC') {
      return 'oldest';
    } else if (sortBy == 'score' && sortOrder == 'DESC') {
      return 'highest_rated';
    } else if (sortBy == 'score' && sortOrder == 'ASC') {
      return 'lowest_rated';
    } else {
      return 'newest';
    }
  }

  List<Widget> _buildInteractionButtons(
      ThemeData theme, ColorScheme colorScheme) {
    final dynamic postState = widget.isOffline
        ? _PostStateOffline(widget.offlinePost!)
        : ref.watch(postProvider(widget.postId));
    final post = postState.post;

    // In offline mode, disable download (already downloaded) and like/dislike
    if (widget.isOffline) {
      return [
        IconButton(
          icon: const Icon(Icons.offline_pin),
          onPressed: null, // Disabled
          tooltip: 'Offline Mode',
        ),
        const SizedBox(width: 5),
        TextButton.icon(
          style: TextButton.styleFrom(
            splashFactory: InkRipple.splashFactory,
            overlayColor: Colors.grey[800],
          ),
          icon: const Icon(Icons.thumb_up_outlined),
          label: Text('${postState.likeCount}'),
          onPressed: null, // Disabled in offline mode
        ),
        const SizedBox(width: 5),
        TextButton.icon(
          style: TextButton.styleFrom(
            splashFactory: InkRipple.splashFactory,
            overlayColor: Colors.grey[800],
          ),
          icon: const Icon(Icons.thumb_down_outlined),
          label: Text('${postState.dislikeCount}'),
          onPressed: null, // Disabled in offline mode
        ),
      ];
    }

    // Show download button if there's a media attachment
    final hasMediaAttachment = post != null &&
        (post.videoAttachments.isNotEmpty || post.audioAttachments.isNotEmpty);

    Future<void> showDownloadDialog() async {
      if (post == null || selectedAttachment == null) return;

      await FPDownloadDialog.show(
        context,
        post: post,
        attachment: selectedAttachment,
        creatorName: post.creator?.title ?? 'Unknown',
        channelName: post.channel?.title,
      );
    }

    Future<void> showShareDialog() async {
      final mediaService = ref.read(mediaPlayerServiceProvider.notifier);
      mediaService.pause();
      final String postId = widget.postId;
      final String attachmentId = _selectedAttachmentId ?? '';
      final WhiteLabel whiteLabel = await whitelabels.getSelectedWhitelabel();
      final timestampController = TextEditingController(
        text: _formatTimestampForInput(mediaService.currentPosition.inSeconds),
      );
      // Initialize the base URL
      String shareUrl =
          'https://www.${whiteLabel.domain}/post/$postId?a=$attachmentId';
      bool includeTimestamp = false; // Reset the timestamp flag
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text('Share Options'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: SelectableText(
                          shareUrl,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Include Timestamp'),
                        Switch(
                          value: includeTimestamp,
                          onChanged: (value) {
                            setState(() {
                              includeTimestamp = value;
                              shareUrl =
                                  'https://www.${whiteLabel.domain}/post/$postId?a=$attachmentId';
                              if (includeTimestamp) {
                                final timestamp =
                                    mediaService.currentPosition.inSeconds;
                                shareUrl += '&t=$timestamp';
                              }
                            });
                          },
                        ),
                      ],
                    ),
                    if (includeTimestamp) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              decoration: InputDecoration(
                                labelText: 'Timestamp (HH:MM:SS or seconds)',
                                hintText: 'e.g., 1:23 or 83',
                                border: const OutlineInputBorder(),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              controller: timestampController,
                              onChanged: (value) {
                                if (value.isNotEmpty) {
                                  final timestamp = _parseTimestamp(value);
                                  setState(() {
                                    shareUrl =
                                        'https://www.${whiteLabel.domain}/post/$postId?a=$attachmentId&t=$timestamp';
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ]
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: shareUrl));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Link copied to clipboard')),
                        );
                      }
                      Navigator.of(context).pop();
                    },
                    child: const Text('Copy Link'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ],
              );
            },
          );
        },
      );
    }

    return [
      IconButton(
        icon: const Icon(Icons.share),
        onPressed: showShareDialog,
      ),
      const SizedBox(width: 5),
      if (hasMediaAttachment) ...[
        IconButton(
          icon: const Icon(Icons.download),
          onPressed: showDownloadDialog,
        ),
        const SizedBox(width: 5),
      ],
      TextButton.icon(
        style: TextButton.styleFrom(
          splashFactory: InkRipple.splashFactory,
          overlayColor: Colors.grey[800],
        ),
        icon: AnimatedTheme(
          data: theme.copyWith(
            iconTheme: IconThemeData(
              color: postState.isLiked
                  ? colorScheme.primary
                  : colorScheme.onSurface,
            ),
          ),
          duration: const Duration(milliseconds: 200),
          child: const Icon(Icons.thumb_up_outlined),
        ),
        label: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            color:
                postState.isLiked ? colorScheme.primary : colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
          child: Text('${postState.likeCount}'),
        ),
        onPressed: () =>
            ref.read(postProvider(widget.postId).notifier).toggleLike(),
      ),
      const SizedBox(width: 5),
      TextButton.icon(
        style: TextButton.styleFrom(
          splashFactory: InkRipple.splashFactory,
          overlayColor: Colors.grey[800],
        ),
        icon: AnimatedTheme(
          data: theme.copyWith(
            iconTheme: IconThemeData(
              color: postState.isDisliked
                  ? colorScheme.primary
                  : colorScheme.onSurface,
            ),
          ),
          duration: const Duration(milliseconds: 200),
          child: const Icon(Icons.thumb_down_outlined),
        ),
        label: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            color: postState.isDisliked
                ? colorScheme.primary
                : colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
          child: Text('${postState.dislikeCount}'),
        ),
        onPressed: () =>
            ref.read(postProvider(widget.postId).notifier).toggleDislike(),
      ),
    ];
  }

  Widget _buildMainContent(
      BoxConstraints constraints, ThemeData theme, ColorScheme colorScheme) {
    final dynamic postState = widget.isOffline
        ? _PostStateOffline(widget.offlinePost!)
        : ref.watch(postProvider(widget.postId));
    final post = postState.post;
    if (post == null) return const SizedBox.shrink();
    Future(() => rootLayoutKey.currentState?.setAppBar(Text(post.title ?? '')));
    final isSmall = constraints.maxWidth <= 700;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        if (selectedAttachment != null &&
            selectedAttachment.isProcessing is bool &&
            selectedAttachment.isProcessing)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                color: colorScheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text('This content is still processing',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      )),
                ),
              ),
            ),
          ),
        if (isSmall)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AutoSizeText(
                post.title ?? 'Unknown Title',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
                stepGranularity: 0.25,
                textScaleFactor: 0.75,
              ),
              post.tags.isNotEmpty == true
                  ? Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: post.tags
                          .map((tag) => Text(
                                '#$tag',
                                style: TextStyle(color: colorScheme.primary),
                              ))
                          .toList(),
                    )
                  : const SizedBox.shrink(),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _buildInteractionButtons(theme, colorScheme),
              ),
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title ?? 'Unknown Title',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (post.tags.isNotEmpty == true)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: post.tags
                            .map((tag) => Text(
                                  '#$tag',
                                  style: TextStyle(color: colorScheme.primary),
                                ))
                            .toList(),
                      ),
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: _buildInteractionButtons(theme, colorScheme),
              ),
            ],
          ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () {
            if (post.creator?.urlname == post.channel?.urlname) {
              context.go('/channel/${post.creator?.urlname}');
            } else {
              context.go(
                  '/channel/${post.creator?.urlname}/${post.channel?.urlname}');
            }
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                backgroundImage: post.channel?.icon?.path != null &&
                        (post.channel?.icon?.path ?? '').isNotEmpty
                    ? CachedNetworkImageProvider(post.channel?.icon?.path ?? '')
                    : AssetImage('assets/placeholder.png'),
                radius: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.channel?.title ?? 'Unknown Creator',
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      post.releaseDate != null
                          ? 'Posted ${DateFormat('MMMM dd, yyyy').format(post.releaseDate!)}'
                          : '',
                      style: TextStyle(
                        color: theme.textTheme.titleMedium?.color,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if ((post.attachmentOrder.length) > 1) ...[
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints:
                const BoxConstraints(maxHeight: 98), // Increased height
            child: Scrollbar(
              controller: _attachmentScrollController,
              thumbVisibility: true,
              radius: const Radius.circular(5),
              interactive: true, // Allow interactive scrollbar
              child: Padding(
                padding:
                    const EdgeInsets.only(bottom: 12), // More bottom padding
                child: SingleChildScrollView(
                  controller: _attachmentScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                    child: Row(
                      children: [
                        ...List.generate(post.attachmentOrder.length, (index) {
                          final id = post.attachmentOrder[index];
                          Widget? attachmentWidget;
                          // Find the attachment by ID
                          for (final video in post.videoAttachments) {
                            if (video.id == id) {
                              attachmentWidget = StateCard(
                                title: video.title,
                                subtitle: "Video",
                                thumbnail: Image.network(
                                  video.thumbnail.path ?? '',
                                  fit: BoxFit.cover,
                                ),
                                topIcon: const Icon(
                                  Icons.videocam,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                isViewing: false,
                                isSelected: id == _selectedAttachmentId,
                                onTap: () {
                                  setState(() {
                                    _selectedAttachmentId = id;
                                    _mediaContentFuture =
                                        _buildMediaContent(); // Rebuild media content
                                  });
                                },
                              );
                              break;
                            }
                          }
                          for (final audio in post.audioAttachments) {
                            if (audio.id == id) {
                              attachmentWidget = StateCard(
                                title: audio.title,
                                subtitle: "Audio",
                                thumbnail: Container(
                                  color: Colors.grey[900],
                                  child: const Center(
                                    child: Icon(
                                      Icons.audiotrack,
                                      color: Colors.white,
                                      size: 48,
                                    ),
                                  ),
                                ),
                                topIcon: const Icon(
                                  Icons.audiotrack,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                isViewing: false,
                                isSelected: id == _selectedAttachmentId,
                                onTap: () {
                                  setState(() {
                                    _selectedAttachmentId = id;
                                    _mediaContentFuture =
                                        _buildMediaContent(); // Rebuild media content
                                  });
                                },
                              );
                              break;
                            }
                          }
                          for (final picture in post.pictureAttachments) {
                            if (picture.id == id) {
                              attachmentWidget = StateCard(
                                title: picture.title,
                                subtitle: "Picture",
                                thumbnail: Image.network(
                                  picture.thumbnail.path ?? '',
                                  fit: BoxFit.cover,
                                ),
                                topIcon: const Icon(
                                  Icons.image,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                isViewing: false,
                                isSelected: id == _selectedAttachmentId,
                                onTap: () {
                                  setState(() {
                                    _selectedAttachmentId = id;
                                    _mediaContentFuture =
                                        _buildMediaContent(); // Rebuild media content
                                  });
                                },
                              );
                              break;
                            }
                          }
                          for (final gallery in post.galleryAttachments) {
                            if (gallery.id == id) {
                              attachmentWidget = StateCard(
                                title: gallery.title,
                                subtitle: "Gallery",
                                thumbnail: Image.network(
                                  gallery.thumbnail.path ?? '',
                                  fit: BoxFit.cover,
                                ),
                                topIcon: const Icon(
                                  Icons.photo_library,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                isViewing: false,
                                isSelected: id == _selectedAttachmentId,
                                onTap: () {
                                  setState(() {
                                    _selectedAttachmentId = id;
                                    _mediaContentFuture =
                                        _buildMediaContent(); // Rebuild media content
                                  });
                                },
                              );
                              break;
                            }
                          }
                          if (attachmentWidget == null) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: EdgeInsets.only(
                              right: index == post.attachmentOrder.length - 1
                                  ? 0
                                  : 16,
                            ),
                            child: attachmentWidget,
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (post.text != null && post.text!.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: postState.isExpanded ? double.infinity : 48.0,
                    ),
                    child: ClipRect(
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: HtmlWidget(
                            post.text ?? '',
                            key: UniqueKey(),
                            factoryBuilder: () => _PostWidgetFactory(),
                            textStyle: TextStyle(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!postState.isExpanded)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 24.0,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              theme.scaffoldBackgroundColor.withAlpha(0),
                              theme.scaffoldBackgroundColor,
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (post.text?.length != null && post.text!.length > 25)
                Center(
                  child: TextButton(
                    onPressed: () => ref
                        .read(postProvider(widget.postId).notifier)
                        .toggleExpanded(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          postState.isExpanded ? 'Show Less' : 'Show More',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        Icon(
                          postState.isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        if (postState.isWan)
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 325),
                child: ShowInfoCard(
                    preshowtime: postState.preShowRange ?? '',
                    mainshowtime: postState.mainShowRange ?? '',
                    preshowlength: postState.preShowDuration ?? '',
                    mainshowlength: postState.mainShowDuration ?? '',
                    lateness: postState.hundredpercentlate
                        ? '${postState.letsBeHonestItsLateTime} ${postState.latenessString}'
                        : postState.letsBeHonestItsLateTime ?? '',
                    late: postState.hundredpercentlate),
              ),
            ),
          ),
        Divider(),
        // Hide comments section in offline mode
        if (!widget.isOffline) ...[
          Row(
            children: [
              if (rootLayoutKey.currentState?.user?.profileImage?.path != null)
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.grey[800],
                  backgroundImage: NetworkImage(
                    rootLayoutKey.currentState?.user?.profileImage?.path ?? '',
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    TextField(
                      controller: _commentController,
                      onChanged: (value) {
                        setState(() {
                          _currentLength = value.length;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Write a Comment',
                        hintStyle: TextStyle(color: Colors.grey[400]),
                        border: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey[800]!),
                        ),
                      ),
                    ),
                    AnimatedCrossFade(
                      firstChild: const SizedBox.shrink(),
                      secondChild: Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          children: [
                            Text(
                              '$_currentLength/4500',
                              style: TextStyle(
                                color: _currentLength > 4500
                                    ? Colors.red
                                    : Colors.grey[400],
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _commentController.clear();
                                  _currentLength = 0;
                                });
                              },
                              style: TextButton.styleFrom(
                                splashFactory: InkRipple.splashFactory,
                                overlayColor: Colors.grey[800],
                              ),
                              child: const Text(
                                'CANCEL',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed:
                                  _currentLength >= 3 && _currentLength <= 4500
                                      ? () async {
                                          final text = _commentController.text;
                                          _commentController.clear();
                                          final comment =
                                              await fpApiRequests.comment(
                                                  (await whitelabels
                                                          .getSelectedWhitelabel())
                                                      .friendlyName,
                                                  post.id ?? '',
                                                  text);
                                          if (comment != null) {
                                            setState(() {
                                              _comments.insert(0, comment);
                                            });
                                          }
                                        }
                                      : null,
                              style: TextButton.styleFrom(
                                splashFactory: InkRipple.splashFactory,
                                overlayColor: Colors.grey[800],
                              ),
                              child: Text(
                                'COMMENT',
                                style: TextStyle(
                                  color: _currentLength >= 3 &&
                                          _currentLength <= 4500
                                      ? Colors.white
                                      : Colors.grey[600],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      crossFadeState: _currentLength > 0
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 200),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text(
                '${post.comments ?? 0} Comments',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: 6),
              DropdownButton<String>(
                value: _getSortDisplayText(),
                hint: const Text(
                  'Sort Comments',
                ),
                icon: const Icon(Icons.sort),
                underline: Container(),
                items: [
                  DropdownMenuItem(
                    value: 'newest',
                    child: const Text('Newest First'),
                    onTap: () {
                      sortBy = 'createdAt';
                      sortOrder = 'DESC';
                      fetchafter = '0';
                      _loadComments();
                    },
                  ),
                  DropdownMenuItem(
                    value: 'oldest',
                    child: const Text('Oldest First'),
                    onTap: () {
                      sortBy = 'createdAt';
                      sortOrder = 'ASC';
                      fetchafter = '0';
                      _loadComments();
                    },
                  ),
                  DropdownMenuItem(
                    value: 'highest_rated',
                    child: const Text('Highest Rated'),
                    onTap: () {
                      sortBy = 'score';
                      sortOrder = 'DESC';
                      fetchafter = '0';
                      _loadComments();
                    },
                  ),
                  DropdownMenuItem(
                    value: 'lowest_rated',
                    child: const Text('Lowest Rated'),
                    onTap: () {
                      sortBy = 'score';
                      sortOrder = 'ASC';
                      fetchafter = '0';
                      _loadComments();
                    },
                  ),
                ],
                onChanged: (String? value) {},
              ),
            ],
          ),
          Column(
            children: [
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _comments.length,
                itemBuilder: (context, index) {
                  return CommentHolder(
                    key: ValueKey(_comments[index].id),
                    comment: _comments[index],
                    content: post,
                  );
                },
              ),
              if (_comments.isEmpty)
                const Center(
                  child: Text("No comments found."),
                ),
              if (_hasMoreComments)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: ElevatedButton(
                    onPressed: _isLoadingComments
                        ? null
                        : () async {
                            setState(() {
                              _isLoadingComments = true;
                            });
                            try {
                              dynamic items;
                              if (fetchafter != '0') {
                                items = await fpApiRequests.getComments(
                                  (await whitelabels.getSelectedWhitelabel())
                                      .friendlyName,
                                  widget.postId,
                                  _pageSize,
                                  sortBy,
                                  sortOrder,
                                  fetchAfter: fetchafter,
                                );
                              } else {
                                items = await fpApiRequests.getComments(
                                  (await whitelabels.getSelectedWhitelabel())
                                      .friendlyName,
                                  widget.postId,
                                  _pageSize,
                                  sortBy,
                                  sortOrder,
                                );
                              }
                              if (!mounted) return;
                              setState(() {
                                _comments.addAll(items);
                                _hasMoreComments = items.length >= _pageSize;
                                if (items.isNotEmpty) {
                                  fetchafter = items.last.id;
                                }
                                _isLoadingComments = false;
                              });
                            } catch (error) {
                              if (mounted) {
                                setState(() {
                                  _isLoadingComments = false;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'An error occurred loading comments'),
                                  ),
                                );
                              }
                            }
                          },
                    child: _isLoadingComments
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Load More Comments'),
                  ),
                ),
            ],
          ),
        ], // End of comments section conditional (offline mode)
        // Show offline mode message when comments are disabled
        if (widget.isOffline)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.offline_pin, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    'Comments unavailable in offline mode',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _loadComments() async {
    setState(() {
      _comments.clear();
      _hasMoreComments = true;
      fetchafter = '0';
    });
    try {
      dynamic items;
      if (fetchafter != '0') {
        items = await fpApiRequests.getComments(
          (await whitelabels.getSelectedWhitelabel()).friendlyName,
          widget.postId,
          _pageSize,
          sortBy,
          sortOrder,
          fetchAfter: fetchafter,
        );
      } else {
        items = await fpApiRequests.getComments(
          (await whitelabels.getSelectedWhitelabel()).friendlyName,
          widget.postId,
          _pageSize,
          sortBy,
          sortOrder,
        );
      }
      if (!mounted) return;
      setState(() {
        _comments.addAll(items);
        _hasMoreComments = items.length >= _pageSize;
        if (items.isNotEmpty) {
          fetchafter = items.last.id;
        }
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('An error occurred loading comments'),
          ),
        );
      }
    }
  }

  Widget _buildRecommendedSection(BoxConstraints constraints,
      {required ScreenLayout layout}) {
    // Hide recommended section in offline mode
    if (widget.isOffline) {
      return SizedBox.shrink();
    }

    final width = layout == ScreenLayout.wide ? 300.0 : constraints.maxWidth;
    final padding = constraints.maxWidth <= 450 ? 4.0 : 2.0;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 16.0, bottom: 8.0),
            child: Text(
              'Recommended',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const ClampingScrollPhysics(),
            itemCount:
                ref.read(postProvider(widget.postId)).recommendedPosts.length,
            itemBuilder: (context, index) {
              final post =
                  ref.read(postProvider(widget.postId)).recommendedPosts[index];
              return Padding(
                padding: EdgeInsets.all(padding),
                child: BlogPostCard(post,
                    response: ref
                        .read(postProvider(widget.postId))
                        .progressMap[post.id]),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PostWidgetFactory extends WidgetFactory with UrlLauncherFactory {
  @override
  void parse(BuildTree tree) {
    // Remove style attributes that contain color-related styles
    final element = tree.element;
    if (element.attributes.containsKey('style')) {
      final style = element.attributes['style']!;
      final newStyle = style
          .split(';')
          .where((prop) =>
              !prop.trim().toLowerCase().startsWith('color:') &&
              !prop.trim().toLowerCase().startsWith('background-color:') &&
              !prop.trim().toLowerCase().startsWith('border-color:'))
          .join(';')
          .trim();
      if (newStyle.isEmpty) {
        element.attributes.remove('style');
      } else {
        element.attributes['style'] = newStyle;
      }
    }
    // Process any inline styles in the HTML
    if (element.attributes.containsKey('color') ||
        element.attributes.containsKey('bgcolor')) {
      element.attributes.remove('color');
      element.attributes.remove('bgcolor');
    }
    super.parse(tree);
  }
}

// Simple offline post state wrapper
class _PostStateOffline {
  final ContentPostV3Response post;

  _PostStateOffline(this.post);

  bool get isLoading => false;
  bool get hasError => false;
  String get error => '';
  Exception? get exception => null;
  int get likeCount => post.likes ?? 0;
  int get dislikeCount => post.dislikes ?? 0;

  // Offline mode doesn't track user interactions
  bool get isLiked => false;
  bool get isDisliked => false;

  // Description expansion state
  bool get isExpanded => false;

  // WAN Show specific properties (disabled in offline mode)
  bool get isWan => false;
  String? get preShowRange => null;
  String? get mainShowRange => null;
  String? get preShowDuration => null;
  String? get mainShowDuration => null;
  bool get hundredpercentlate => false;
  String? get letsBeHonestItsLateTime => null;
  String? get latenessString => null;
}
