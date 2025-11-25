import 'package:floaty/whitelabels.dart';
import 'package:floaty/features/authentication/services/oauth2_service.dart';
import 'package:floaty/features/api/repositories/fpapi.dart';
import 'package:cookie_jar/cookie_jar.dart';

class Middleware {
  final OAuth2Service _oauth2Service = OAuth2Service();
  
  // Feature flag for cookie-based testing
  bool get useCookieAuth => const bool.fromEnvironment('USE_COOKIE_AUTH', defaultValue: false);
  
  Future<bool> isAuthenticated({String? whitelabelFriendlyName}) async {
    
    final whitelabelsToCheck = whitelabelFriendlyName != null
        ? [whitelabels.getWhitelabel(whitelabelFriendlyName)]
        : whitelabels.getWhitelabels();
    
    // Check each whitelabel
    for (var whitelabel in whitelabelsToCheck) {
      
      // Get the auth method for this whitelabel
      final authMethod = await _oauth2Service.getAuthMethod(whitelabel: whitelabel.friendlyName);
      
      // If no auth method is set and we have the USE_COOKIE_AUTH flag, use cookies
      // Otherwise, default to OAuth2
      final useCookie = (authMethod == 'cookie') || (authMethod == null && useCookieAuth);
      
      if (!useCookie) {
        // Check OAuth2 authentication
        final result = await _oauth2Service.isAuthenticated(whitelabel: whitelabel.friendlyName);
        if (result) return true;
      } else {
        // Check cookie authentication
        final cookieJar = fpApiRequests.cookieJar;
        final uri = Uri.parse('https://${whitelabel.domain}/');
        final cookies = await cookieJar.loadForRequest(uri);

        final authCookie = cookies.firstWhere(
          (c) => c.name == whitelabel.cookieName,
          orElse: () => Cookie('', ''),
        );
        
        if (authCookie.name.isNotEmpty && authCookie.value.isNotEmpty) {
          if (authCookie.expires != null &&
              authCookie.expires!.isAfter(DateTime.now())) {
            return true;
          } else {
            cookieJar.delete(uri);
            await whitelabels.removeLoggedInLabel(whitelabel.friendlyName);
          }
        }
      }
    }
    
        return false;
  }
}