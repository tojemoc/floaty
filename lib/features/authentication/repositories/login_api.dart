import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:floaty/settings.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:floaty/whitelabels.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:get_it/get_it.dart';

final LoginApi loginApi = GetIt.I<LoginApi>();

class LoginApi {
  PackageInfo? packageInfo;
  String userAgent = 'FloatyClient/error, CFNetwork';
  String? token;
  late final PersistCookieJar cookieJar;
  late final Dio _dio;

  LoginApi() {
    _init();
  }

  void _init() async {
    packageInfo = await PackageInfo.fromPlatform();
    const flavor =
        String.fromEnvironment('FLUTTER_FLAVOR', defaultValue: 'release');
    userAgent =
        'FloatyClient/${packageInfo?.version}+${packageInfo?.buildNumber}-$flavor, CFNetwork';
    final dir = await getApplicationSupportDirectory();
    cookieJar = PersistCookieJar(
      storage: FileStorage('${dir.path}/.cookies/'),
    );

    _dio = Dio(BaseOptions(
      responseType: ResponseType.plain,
      headers: {
        'User-Agent': userAgent,
        'Content-Type': 'application/json',
      },
      validateStatus: (_) => true,
    ));

    _dio.interceptors.add(CookieManager(cookieJar));
  }

  Future<Map<String, dynamic>> captcha(String whitelabel) async {
    final whiteLabel = whitelabels.getWhitelabel(whitelabel);
    final url = '${whiteLabel.apiUrl}/v3/auth/captcha/info';
    final response = await _dio.get(
      url,
    );

    final resData = jsonDecode(response.data);

    return resData;
  }

// do not messsage me about this absolute garbage code please - bw86
// back here like 3 months later because well it broke - bw86 - 20/01/2025
// migration to dio and cookiejar because my manual system is ass - bw86 - 15/04/2025
// guess whos back? this time we fix this garbage code once and for all - bw86 - 22/06/2025
  Future<Map<String, dynamic>> login(
      String username, String password, String whitelabel) async {
    final whiteLabel = whitelabels.getWhitelabel(whitelabel);
    final url = '${whiteLabel.apiUrl}/v2/auth/login';

    final response = await _dio.post(
      url,
      data: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    final resData = jsonDecode(response.data);

    if (response.statusCode == 200) {
      if (resData['needs2FA'] == true) {
        await settings.setBool('${whiteLabel.friendlyName}-2faRequired', true);
      } else {
        await whitelabels.addLoggedInLabel(
            '${whiteLabel.friendlyName}-${resData['user']['id']}');
      }
    }

    return resData;
  }

  Future<Map<String, dynamic>> twofa(String code, String whitelabel) async {
    final whiteLabel = whitelabels.getWhitelabel(whitelabel);
    final url = '${whiteLabel.apiUrl}/v2/auth/checkFor2faLogin';
    final response = await _dio.post(
      url,
      data: jsonEncode({
        'token': code,
      }),
    );

    final resData = jsonDecode(response.data);

    if (response.statusCode == 200 && resData['needs2FA'] == false) {
      await settings.setBool("${whiteLabel.friendlyName}-2faRequired", false);
      await whitelabels.addLoggedInLabel(
          '${whiteLabel.friendlyName}-${resData['user']['id']}');
    }

    return resData;
  }

  Future<Map<String, dynamic>> logout(String whitelabel) async {
    final whiteLabel = whitelabels.getWhitelabel(whitelabel);
    final url = '${whiteLabel.apiUrl}/v2/auth/logout';
    final response = await _dio.post(
      url,
    );

    final resData = jsonDecode(response.data);

    return resData;
  }
}
