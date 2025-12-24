import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:floaty/features/player/controllers/media_player_service.dart';

final mediaPlayerServiceProvider =
    NotifierProvider<MediaPlayerService, MediaPlayerState>(
  MediaPlayerService.new,
);
