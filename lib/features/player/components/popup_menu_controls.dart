import 'package:flutter/material.dart';

import '../controllers/media_player_service.dart';
import '../models/video_quality.dart';

PopupMenuItem<String> subtitlePopupMenuItem({
  required MediaPlayerService mediaService,
  required List<Map<String, dynamic>> textTracks,
}) {
  return PopupMenuItem<String>(
    value: 'subtitles',
    child: PopupMenuButton<int>(
      child: const Text('Subtitles'),
      itemBuilder: (context) => textTracks.asMap().entries.map((entry) {
        final index = entry.key;
        final track = entry.value;
        return PopupMenuItem<int>(
          value: index,
          child: Row(
            children: [
              Text(track['language'] ?? 'Unknown'),
              if (index == mediaService.currentSubtitleTrackIndex)
                const Padding(
                  padding: EdgeInsets.only(left: 8.0),
                  child: Icon(Icons.check, size: 16),
                ),
            ],
          ),
        );
      }).toList(),
      onSelected: (index) {
        mediaService.setSubtitleTrack(index);
      },
    ),
  );
}

PopupMenuItem<String> qualityPopupMenuItem({
  required MediaPlayerService mediaService,
  required List<VideoQuality> qualities,
}) {
  return PopupMenuItem<String>(
    value: 'quality',
    child: PopupMenuButton<VideoQuality>(
      child: Text('Quality'),
      itemBuilder: (context) => qualities.map((quality) {
        return PopupMenuItem<VideoQuality>(
          value: quality,
          child: Row(
            children: [
              Text(quality.label),
              if (quality == mediaService.currentQuality)
                const Padding(
                  padding: EdgeInsets.only(left: 8.0),
                  child: Icon(Icons.check, size: 16),
                ),
            ],
          ),
        );
      }).toList(),
      onSelected: (quality) {
        mediaService.changeQuality(quality);
      },
    ),
  );
}

PopupMenuItem<String> playbackSpeedPopupMenuItem({
  required MediaPlayerService mediaService,
}) {
  List<double> playbackSpeeds = [0.5, 1.0, 1.25, 1.5, 1.75, 2.0];
  return PopupMenuItem<String>(
    value: 'playback_speed',
    child: PopupMenuButton<double>(
      child: Text('Playback Speed'),
      itemBuilder: (context) => [
        ...playbackSpeeds.map((speed) {
          return PopupMenuItem(
              value: speed,
              child: Row(
                children: [
                  Text('${speed}x'),
                  if (mediaService.player.state.rate == speed)
                    const Padding(
                      padding: EdgeInsets.only(left: 8.0),
                      child: Icon(Icons.check, size: 16),
                    ),
                ],
              ));
        }),
        PopupMenuItem(
          value: mediaService.player.state.rate,
          child: Row(
            children: [
              Text('Custom'),
              if (!playbackSpeeds.contains(mediaService.player.state.rate))
                const Padding(
                  padding: EdgeInsets.only(left: 8.0),
                  child: Icon(Icons.check, size: 16),
                ),
            ],
          ),
          onTap: () => _showCustomSpeedDialog(context, mediaService),
        ),
      ],
      onSelected: (speed) {
        mediaService.setSpeed(speed);
      },
    ),
  );
}

void _showCustomSpeedDialog(
  BuildContext context,
  MediaPlayerService mediaService,
) {
  double customSpeed = mediaService.player.state.rate;
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return AlertDialog(
            title: const Text('Select Playback Speed'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Slider(
                  value: customSpeed,
                  min: 0.1,
                  max: 4.0,
                  divisions: 100,
                  label: '${customSpeed.toStringAsFixed(1)}x',
                  onChanged: (value) {
                    setState(() {
                      customSpeed = value;
                    });
                  },
                ),
                Text('${customSpeed.toStringAsFixed(1)}x'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  mediaService.setSpeed(customSpeed);
                },
                child: const Text('Set Speed'),
              ),
            ],
          );
        },
      );
    },
  );
}
