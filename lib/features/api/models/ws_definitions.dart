import 'package:json_annotation/json_annotation.dart';

part 'ws_definitions.g.dart';

/// Enum for poll event types
enum PollEventType {
  @JsonValue('pollOpen')
  pollOpen,

  @JsonValue('pollUpdateTally')
  pollUpdateTally,
}

/// Model for a poll
@JsonSerializable()
class Poll {
  @JsonKey(name: 'id')
  final String? id;
  final String? type;
  final String? creator;
  final String? title;
  final List<String> options;
  @JsonKey(name: 'startDate')
  final DateTime startDate;
  @JsonKey(name: 'endDate')
  final DateTime? endDate;
  @JsonKey(name: 'finalTallyApproximate')
  final List<int>? finalTallyApproximate;
  @JsonKey(name: 'finalTallyReal')
  final List<int>? finalTallyReal;
  @JsonKey(name: 'runningTally')
  final RunningTally runningTally;
  final bool? voted;
  final Map<String, dynamic>? voteInfo;

  Poll({
    this.id,
    this.type,
    this.creator,
    this.title,
    required this.options,
    required this.startDate,
    this.endDate,
    this.finalTallyApproximate,
    this.finalTallyReal,
    required this.runningTally,
    this.voted,
    this.voteInfo,
  });

  factory Poll.fromJson(Map<String, dynamic> json) {
    try {
      // Handle case where poll data is nested under 'poll' key
      final pollData = json['poll'] ?? json;

      return Poll(
        id: (pollData['id'] as String?) ?? 'unknown',
        type: (pollData['type'] as String?) ?? 'unknown',
        creator: (pollData['creator'] as String?) ?? 'unknown',
        title: (pollData['title'] as String?) ?? 'Untitled Poll',
        options: (pollData['options'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        startDate: pollData['startDate'] != null
            ? DateTime.tryParse(pollData['startDate'].toString()) ??
                DateTime.now()
            : DateTime.now(),
        endDate: pollData['endDate'] != null
            ? DateTime.tryParse(pollData['endDate'].toString())
            : null,
        runningTally: pollData['runningTally'] != null
            ? RunningTally.fromJson(
                Map<String, dynamic>.from(pollData['runningTally']))
            : RunningTally(tick: 0, counts: []),
        finalTallyApproximate: pollData['finalTallyApproximate'] != null
            ? List<int>.from(pollData['finalTallyApproximate'] as List)
            : null,
        finalTallyReal: pollData['finalTallyReal'] != null
            ? List<int>.from(pollData['finalTallyReal'] as List)
            : null,
        voted: pollData['voted'] as bool?,
        voteInfo: pollData['voteInfo'] != null
            ? Map<String, dynamic>.from(pollData['voteInfo'])
            : null,
      );
    } catch (e) {
      rethrow;
    }
  }
  Map<String, dynamic> toJson() => _$PollToJson(this);
}

/// Tally at a point in time
@JsonSerializable()
class RunningTally {
  final int tick;
  final List<int> counts;

  RunningTally({required this.tick, required this.counts});

  factory RunningTally.fromJson(Map<String, dynamic> json) => RunningTally(
        tick: json['tick'] as int,
        counts: (json['counts'] as List<dynamic>).map((e) => e as int).toList(),
      );

  Map<String, dynamic> toJson() => {
        'tick': tick,
        'counts': counts,
      };
}

/// Tally at a point in time
@JsonSerializable()
class TallyUpdate {
  @JsonKey(name: 'tick')
  final int tick;
  final List<int> counts;
  final String pollId;

  TallyUpdate({required this.tick, required this.counts, required this.pollId});

  factory TallyUpdate.fromJson(Map<String, dynamic> json) =>
      _$TallyUpdateFromJson(json);
  Map<String, dynamic> toJson() => _$TallyUpdateToJson(this);
}
