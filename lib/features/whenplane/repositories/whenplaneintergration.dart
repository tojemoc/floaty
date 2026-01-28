import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:web_socket_client/web_socket_client.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:get_it/get_it.dart';

final WhenPlaneIntegration whenPlaneIntegration =
    GetIt.I<WhenPlaneIntegration>();

class WhenPlaneIntegration {
  static String baseUrl = 'https://whenplane.com/api';
  PackageInfo? packageInfo;
  String userAgent = 'FloatyClient/error';

  final List<String> alternates = [
    "late",
    "\"late\"",
    "soon™",
    "close enough",
    "punctually impaired",
    "punctually challenged",
    "belated",
    "procrastinated",
    "Linus Late Tips",
    "Late-nus",
    "The Late Show",
    "fashionably late",
    "tardy",
    "diligently delayed",
    "gregariously unpunctual"
  ];

  late Dio _dio;

  WhenPlaneIntegration() {
    initHttp();
    initUserAgent();
  }

  Future<void> initUserAgent() async {
    packageInfo = await PackageInfo.fromPlatform();
    const flavor =
        String.fromEnvironment('FLUTTER_FLAVOR', defaultValue: 'release');
    userAgent =
        'FloatyClient/${packageInfo?.version}+${packageInfo?.buildNumber}-$flavor';
  }

  Future<void> initHttp() async {
    final dir = await getApplicationSupportDirectory();
    final cookieJar = PersistCookieJar(
      storage: FileStorage('${dir.path}/.cookies/'),
    );
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      responseType: ResponseType.plain,
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': userAgent,
      },
    ));
    _dio.interceptors.add(CookieManager(cookieJar));
  }

  Future<dynamic> fetchData(String apiUrl) async {
    try {
      final response = await _dio.get('$baseUrl/$apiUrl');
      return response.data.toString();
    } on DioException catch (e) {
      return {'error': e.response?.statusCode ?? 0};
    } catch (e) {
      return {'error': 0}; // For non-HTTP errors
    }
  }

  Future<dynamic> getPreviousShowInfo(String date) async {
    return await fetchData('history/show/$date');
  }

  String newPhrase() {
    return alternates[math.Random().nextInt(alternates.length)];
  }

  Future<String> lateness() async {
    String res = await fetchData('latenesses');
    return res;
  }

  Future<String> alternateStartTimes() async {
    String res = await fetchData('alternateStartTimes');
    return res;
  }

  Stream<String> streamWebsocket() async* {
    try {
      final socket = WebSocket(
        Uri.parse('wss://sockets.whenplane.com/socket?events=aggregate'),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': userAgent,
        },
      );

      await for (final message in socket.messages) {
        yield message;
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<dynamic> floatplanestats() async {
    return fetchData(
        'floatplane?fast=false&description=false&d=${DateTime.now().millisecondsSinceEpoch}');
  }

  bool isBefore(DateTime a, DateTime b) {
    return a.isBefore(b);
  }

  DateTime getNextWAN(DateTime now,
      {bool buffer = true,
      List<Map<String, dynamic>>? alternateTimes,
      bool? hasDone}) {
    DateTime adjustedNow = now;
    // Adjust 'now' for loose wan for LTX (2023-07-29)
    if (adjustedNow.year == 2023 &&
        adjustedNow.month == 7 &&
        adjustedNow.day == 29) {
      adjustedNow = adjustedNow.subtract(Duration(days: 1));
    }
    DateTime wanDate = getLooseWAN(adjustedNow);

    while (wanDate.weekday != DateTime.friday) {
      wanDate = wanDate.add(Duration(days: 1));
    }

    bool shouldStay;
    if (buffer) {
      if (hasDone != null) {
        shouldStay = !hasDone;
      } else {
        // JS: shouldStay = now.getTime() - wanDate.toJSDate().getTime() > 5 * 60 * 60 * 1e3;
        shouldStay =
            now.millisecondsSinceEpoch - wanDate.millisecondsSinceEpoch >
                5 * 60 * 60 * 1000;
      }
    } else {
      shouldStay = false;
    }

    if (wanDate.isBefore(now) && !shouldStay) {
      wanDate = wanDate.add(Duration(days: 7));
    }

    // prevent counting down til next wan if current wan hasn't come yet
    if (wanDate.millisecondsSinceEpoch - now.millisecondsSinceEpoch >
            6 * 24 * 60 * 60 * 1000 &&
        shouldStay) {
      wanDate = wanDate.subtract(Duration(days: 7));
    }

    // If the show ends before the normal time, go ahead and skip over it
    if (hasDone == true &&
        wanDate.millisecondsSinceEpoch - now.millisecondsSinceEpoch <
            24 * 60 * 60 * 1000) {
      wanDate = wanDate.add(Duration(days: 7));
    }

    // Apply alternateTimes adjustments
    if (alternateTimes != null) {
      String dateString =
          "${wanDate.year}/${addZero(wanDate.month)}/${addZero(wanDate.day)}";
      Map<String, dynamic> adjustment = alternateTimes.firstWhere(
        (t) => t['date'] == dateString,
        orElse: () => {},
      );
      if (adjustment.isNotEmpty) {
        if (adjustment['days'] != null) {
          wanDate = wanDate.add(Duration(days: adjustment['days']));
        }
        wanDate = DateTime(
          wanDate.year,
          wanDate.month,
          wanDate.day,
          adjustment['hour'] ?? wanDate.hour,
          adjustment['minute'] ?? wanDate.minute,
        );
      }
    }

    // 7/18/2023 skipped due to production shutdown (from GN callout)
    if (wanDate.year == 2023 && wanDate.month == 8 && wanDate.day == 18) {
      wanDate = wanDate.add(Duration(days: 7));
    }

    return wanDate;
  }

  DateTime getLooseWAN(DateTime now) {
    int year = now.toUtc().year;
    int month = now.toUtc().month;
    int day = now.toUtc().hour <= 3 ? now.toUtc().day - 1 : now.toUtc().day;

    if (day <= 0) {
      month -= 1;
      day = DateTime(year, month + 1, 0).day + day;
    }

    if (month <= 0) {
      year -= 1;
      month += 12;
      day = DateTime(year, month + 1, 0).day;
    }

    //return utc instead of vancouver time so .toLocal() works
    return DateTime.utc(year, month, day, 23, 30);
  }

  String getUTCDate(DateTime date) {
    if (date.hour < 2) {
      date = date.subtract(Duration(days: 1));
    }
    return DateFormat('yyyy/MM/dd').format(date);
  }

  int dateToNumber(String date) {
    return int.parse(date.replaceAll("/", ""));
  }

  String addZero(int n) {
    return n > 9 ? "$n" : "0$n";
  }

  Map<String, dynamic> getTimeUntil(DateTime date,
      {DateTime? now, bool abs = true}) {
    now ??= DateTime.now();
    int distance = date.difference(now).inMilliseconds;
    bool late = false;
    if (distance < 0) {
      late = true;
      distance = abs ? distance.abs() : distance;
    }

    String string = timeString(distance);

    return {'string': string, 'late': late, 'distance': distance};
  }

  String timeString(int distance,
      {bool long = false, bool showSeconds = true}) {
    int days = (distance / (1000 * 60 * 60 * 24)).floor();
    int hours = ((distance % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60)).floor();
    int minutes = ((distance % (1000 * 60 * 60)) / (1000 * 60)).floor();
    int seconds = ((distance % (1000 * 60)) / 1000).floor();

    String d = long ? (days != 1 ? " days " : " day ") : "d ";
    String h = long ? (hours != 1 ? " hours " : " hour ") : "h ";
    String m = long ? (minutes != 1 ? " minutes " : " minute ") : "m ";
    String s = long ? (seconds != 1 ? " seconds " : " second ") : "s ";

    String daysS = days > 0 ? "$days$d" : "";
    String hoursS = hours > 0 ? "$hours$h" : "";
    String minutesS = minutes > 0 ? "$minutes$m" : "";
    String and =
        long && (daysS.isNotEmpty || hoursS.isNotEmpty || minutesS.isNotEmpty)
            ? "and "
            : "";
    String secondsS = "$seconds$s";

    return "$daysS$hoursS$minutesS${showSeconds ? "$and$secondsS" : minutes > 0 ? "" : "<1 minute"}";
  }

  String timeStringHours(int distance, {bool long = false}) {
    int hours = (distance / (1000 * 60 * 60)).floor();
    int minutes = ((distance % (1000 * 60 * 60)) / (1000 * 60)).floor();
    int seconds = ((distance % (1000 * 60)) / 1000).floor();

    String h = long ? (hours != 1 ? " hours " : " hour ") : "h ";
    String m = long ? (minutes != 1 ? " minutes " : " minute ") : "m ";
    String s = long ? (seconds != 1 ? " seconds " : " second ") : "s ";

    String hoursS = hours > 0 ? "$hours$h" : "";
    String minutesS = minutes > 0 ? "$minutes$m" : "";
    String and =
        long && (hoursS.isNotEmpty || minutesS.isNotEmpty) ? "and " : "";
    String secondsS = "$seconds$s";

    return "$hoursS$minutesS$and$secondsS";
  }

  DateTime getPreviousWAN(DateTime now,
      {List<Map<String, dynamic>>? alternateTimes}) {
    DateTime wanDate = getLooseWAN(now);

    while (wanDate.weekday != DateTime.friday) {
      wanDate = wanDate.subtract(Duration(days: 1));
    }

    if (isBefore(now, wanDate)) {
      wanDate = wanDate.subtract(Duration(days: 7));
    }

    // Apply alternateTimes adjustments
    if (alternateTimes != null) {
      String dateString =
          "${wanDate.year}/${addZero(wanDate.month)}/${addZero(wanDate.day)}";
      Map<String, dynamic> adjustment = alternateTimes.firstWhere(
        (t) => t['date'] == dateString,
        orElse: () => {},
      );
      if (adjustment.isNotEmpty) {
        if (adjustment['days'] != null) {
          wanDate = wanDate.add(Duration(days: adjustment['days']));
        }
        wanDate = DateTime(
          wanDate.year,
          wanDate.month,
          wanDate.day,
          adjustment['hour'] ?? wanDate.hour,
          adjustment['minute'] ?? wanDate.minute,
        );
      }
    }

    // 7/18/2023 skipped due to production shutdown (from GN callout)
    if (wanDate.year == 2023 && wanDate.month == 8 && wanDate.day == 18) {
      wanDate = wanDate.subtract(Duration(days: 7));
    }

    return wanDate;
  }

  DateTime getClosestWan(DateTime now,
      {List<Map<String, dynamic>>? alternateTimes}) {
    DateTime next =
        getNextWAN(now, buffer: false, alternateTimes: alternateTimes);
    DateTime previous = getPreviousWAN(now, alternateTimes: alternateTimes);

    int distanceToNext =
        (next.millisecondsSinceEpoch - now.millisecondsSinceEpoch).abs();
    int distanceToPrevious =
        (previous.millisecondsSinceEpoch - now.millisecondsSinceEpoch).abs();

    return distanceToNext > distanceToPrevious ? previous : next;
  }

  Map<String, dynamic> getNearestWan([DateTime? now]) {
    now ??= DateTime.now();
    DateTime next = getNextWAN(now, buffer: false);
    DateTime previous = getPreviousWAN(now);

    Duration toNext = next.difference(now);
    Duration sincePrevious = now.difference(previous);

    if (toNext < sincePrevious) {
      return {
        'date': next,
        'isNext': true,
        'timeUntil': toNext,
      };
    } else {
      return {
        'date': previous,
        'isNext': false,
        'timeUntil': -sincePrevious, // Negative to indicate it's in the past
      };
    }
  }

  bool isNearWan(DateTime? now) {
    now ??= DateTime.now();
    if (now.weekday == DateTime.friday) {
      return now.hour > 20;
    } else if (now.weekday == DateTime.saturday) {
      return now.hour <= 11;
    } else {
      return false;
    }
  }

  List<String> shortMonths = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec"
  ];

  bool isSameDay(DateTime a, DateTime b) {
    return a.day == b.day && a.month == b.month && a.year == b.year;
  }

  DateTime yesterday() {
    DateTime date = DateTime.now();
    return DateTime(date.year, date.month, date.day - 1);
  }

  String dateTimeToString(DateTime date) {
    return DateFormat('yyyy/MM/dd').format(date);
  }

  Future<String> aggregate() async {
    String res = await fetchData('aggregate');
    return res;
  }

  Future<String> sendVote(String vote, String k) async {
    final response = await Dio().post(
      'https://whenplane.com/?/vote=&for=${Uri.encodeComponent(vote)}&k=$k',
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'Origin': 'https://whenplane.com',
          'User-Agent': userAgent,
        },
      ),
    );
    return response.data.toString();
  }
}
