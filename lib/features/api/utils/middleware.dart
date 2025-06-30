import 'package:floaty/settings.dart';
import 'package:floaty/whitelabels.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cookie_jar/cookie_jar.dart';

class Middleware {
  Future<bool> isAuthenticated({String? whitelabelFriendlyName}) async {
    final dir = await getApplicationSupportDirectory();
    final cookieJar = PersistCookieJar(
      storage: FileStorage('${dir.path}/.cookies/'),
    );

    final whitelabelsToCheck = whitelabelFriendlyName != null
        ? [whitelabels.getWhitelabel(whitelabelFriendlyName)]
        : whitelabels.getWhitelabels();

    for (var whitelabel in whitelabelsToCheck) {
      try {
        final uri = Uri.parse(whitelabel.apiUrl);
        final cookies = await cookieJar.loadForRequest(uri);

        final authCookie = cookies.firstWhere(
          (c) => c.name == whitelabel.cookieName,
          orElse: () => throw Exception('No auth cookie'),
        );

        if (authCookie.expires != null &&
            authCookie.expires!.isAfter(DateTime.now())) {
          return true;
        }
      } catch (_) {
        if (whitelabelFriendlyName != null) {
          return false;
        }
        continue;
      }
    }

    return whitelabelFriendlyName != null;
  }

  Future<bool> twoFAAuthenticated({String? whitelabelFriendlyName}) async {
    final whitelabelsToCheck = whitelabelFriendlyName != null
        ? [whitelabels.getWhitelabel(whitelabelFriendlyName)]
        : whitelabels.getWhitelabels();

    for (var whitelabel in whitelabelsToCheck) {
      var required =
          await settings.getBool('${whitelabel.friendlyName}-2faRequired');
      if (required) {
        return true;
      } else {
        continue;
      }
    }
    return false;
  }
}
