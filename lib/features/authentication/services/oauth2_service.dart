import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:crypto/crypto.dart';
import 'package:floaty/features/api/repositories/fpapi.dart';
import 'package:floaty/features/player/controllers/media_player_service.dart';
import 'package:floaty/features/router/views/root_layout.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http_cache_hive_store/http_cache_hive_store.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:floaty/settings.dart';
import 'package:floaty/whitelabels.dart';
import 'package:window_manager/window_manager.dart';

/// OpenID Connect Discovery Configuration
class OpenIDConfig {
  final String issuer;
  final String authorizationEndpoint;
  final String tokenEndpoint;
  final String userinfoEndpoint;
  final String endSessionEndpoint;
  final String revocationEndpoint;
  final List<String> scopesSupported;
  final List<String> responseTypesSupported;
  final List<String> grantTypesSupported;

  OpenIDConfig({
    required this.issuer,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.userinfoEndpoint,
    required this.endSessionEndpoint,
    required this.revocationEndpoint,
    required this.scopesSupported,
    required this.responseTypesSupported,
    required this.grantTypesSupported,
  });

  factory OpenIDConfig.fromJson(Map<String, dynamic> json) {
    return OpenIDConfig(
      issuer: json['issuer'] as String,
      authorizationEndpoint: json['authorization_endpoint'] as String,
      tokenEndpoint: json['token_endpoint'] as String,
      userinfoEndpoint: json['userinfo_endpoint'] as String,
      endSessionEndpoint: json['end_session_endpoint'] as String,
      revocationEndpoint: json['revocation_endpoint'] as String,
      scopesSupported: List<String>.from(json['scopes_supported'] ?? []),
      responseTypesSupported:
          List<String>.from(json['response_types_supported'] ?? []),
      grantTypesSupported:
          List<String>.from(json['grant_types_supported'] ?? []),
    );
  }
}

class OAuth2Service {
  final Logger _log = Logger('OAuth2Service');
  static final OAuth2Service instance = OAuth2Service();

  static const FlutterAppAuth _appAuth = FlutterAppAuth();
  HttpServer? server;

  // Lock mechanism to prevent concurrent token operations per whitelabel
  final Map<String, Future<String?>> _pendingTokenOperations = {};
  final Map<String, Future<OAuth2Result>> _pendingRefreshOperations = {};

  // feat flag for oauth overrides
  static const bool _useOAuthOverrides =
      bool.fromEnvironment('USE_OAUTH_OVERRIDES', defaultValue: false);
  static const String _overrideClientId =
      String.fromEnvironment('OAUTH_CLIENT_ID');
  static const String _overrideAuthEndpoint =
      String.fromEnvironment('OAUTH_AUTH_ENDPOINT');
  static const String _overrideTokenEndpoint =
      String.fromEnvironment('OAUTH_TOKEN_ENDPOINT');
  static const String _overrideUserinfoEndpoint =
      String.fromEnvironment('OAUTH_USERINFO_ENDPOINT');
  static const String _overrideRevocationEndpoint =
      String.fromEnvironment('OAUTH_REVOCATION_ENDPOINT');

  // generic defaults incase something breaks
  static const String _defaultClientId = 'floaty';
  static const String _redirectUrl = 'uk.bw86.floaty://oauth/callback';
  static const String _redirectUrlDesktop =
      'http://localhost:36479/oauth/callback';
  static const List<String> _scopes = [
    "openid",
    // "videos.download",
    "roles",
    "profile",
    // "user.read",
    // "comments:read",
    "email",
    // "videos.watch",
    "offline_access",
    // "comments:write",
    "basic",

    //UNUSED SCOPES (keep for reference)
    // "web-origins"
    // "phone"
    // "organization"
    // "acr"
    // "address"
  ];

  final Dio _dio;
  OpenIDConfig? _cachedConfig;
  String? _cachedConfigUrl;

  OAuth2Service({Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(validateStatus: (_) => true));

  /// Get the client ID - uses override if flag is enabled, otherwise defaults to floaty
  Future<String> getClientId() async {
    if (_useOAuthOverrides) {
      return _overrideClientId;
    }
    return _defaultClientId;
  }

  /// Fetches OpenID Connect Discovery configuration from the whitelabel
  /// Returns null if config URL is not available (will use fallback defaults)
  Future<OpenIDConfig?> getOpenIDConfig({WhiteLabel? whiteLabel}) async {
    // If using overrides, skip dynamic config fetching
    if (_useOAuthOverrides) {
      return null;
    }

    try {
      final whitelabel =
          whiteLabel ?? await whitelabels.getSelectedWhitelabel();
      final configUrl = whitelabel.oauthconfigurl;

      if (configUrl == null || configUrl.isEmpty) {
        return null;
      }

      // Return cached config if available and URL hasn't changed
      if (_cachedConfig != null && _cachedConfigUrl == configUrl) {
        return _cachedConfig;
      }

      final response = await _dio.get(configUrl);

      if (response.statusCode == 200) {
        final config = OpenIDConfig.fromJson(response.data);

        // Cache the config
        _cachedConfig = config;
        _cachedConfigUrl = configUrl;

        return config;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// Determines if we're running on a platform that supports flutter_appauth
  bool get _canUseAppAuth {
    return !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  }

  /// Gets the appropriate redirect URL for the current platform
  String get _currentRedirectUrl {
    if (_canUseAppAuth) {
      return _redirectUrl;
    } else {
      return _redirectUrlDesktop;
    }
  }

  /// Main login method that chooses the appropriate flow
  Future<OAuth2Result> login({WhiteLabel? whiteLabel}) async {
    try {
      // Try to fetch OpenID configuration (optional)
      await getOpenIDConfig(whiteLabel: whiteLabel);

      if (_canUseAppAuth) {
        return _performMobileAuthFlow(whiteLabel: whiteLabel);
      } else {
        return _performDesktopAuthFlow(whiteLabel: whiteLabel);
      }
    } catch (e) {
      return OAuth2Result.error('Login failed: $e');
    }
  }

  /// Logout method that clears the appropriate whitelabel(s) tokens.
  Future<bool> logout(WhiteLabelWithUser whitelabel) async {
    try {
      final accessToken = await getAccessToken(
        whitelabel: whitelabel.whitelabel.friendlyName,
      );

      // Try to revoke token on server
      if (accessToken != null) {
        await revoke(accessToken);
      }

      // Clear OAuth2 client from cache
      fpApiRequests.clearOAuth2Client(whitelabel.whitelabel.friendlyName);

      // Clear OAuth2 tokens for this whitelabel
      await clearStoredTokens(
        whitelabel: whitelabel.whitelabel.friendlyName,
      );

      // Call logout API endpoint
      await fpApiRequests.logout(whitelabel.whitelabel.friendlyName);

      // Clear cookies (try both with and without www)
      final dir = await getApplicationSupportDirectory();
      final cookieJar = PersistCookieJar(
        storage: FileStorage('${dir.path}/.cookies/'),
      );
      await cookieJar.delete(Uri.parse(
        'https://www.${whitelabel.whitelabel.domain}',
      ));
      await cookieJar.delete(Uri.parse(
        'https://${whitelabel.whitelabel.domain}',
      ));

      // Clear cache
      final hiveStore = HiveCacheStore('${dir.path}/.dio_cache');
      await hiveStore.deleteFromPath(
          RegExp('https://www.${whitelabel.whitelabel.domain}'));

      // Remove from logged in labels
      await whitelabels.removeLoggedInLabel(whitelabel.whitelabel.friendlyName);

      // Update selected whitelabel if needed
      if ((await whitelabels.getFirstLoggedInLabelOrDefault()).friendlyName ==
          (await settings.getKey('whitelabel'))) {
        rootLayoutKey.currentState?.ref
            .read(mediaPlayerServiceProvider.notifier)
            .changeState(MediaPlayerState.none);
      }

      await settings.setKey('whitelabel',
          (await whitelabels.getFirstLoggedInLabelOrDefault()).friendlyName);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Mobile OAuth flow using flutter_appauth
  Future<OAuth2Result> _performMobileAuthFlow({WhiteLabel? whiteLabel}) async {
    try {
      final config = await getOpenIDConfig(whiteLabel: whiteLabel);
      final clientId = await getClientId();

      // Use overrides if flag enabled, otherwise use dynamic config or Floatplane defaults
      final authEndpoint = _useOAuthOverrides
          ? _overrideAuthEndpoint
          : (config?.authorizationEndpoint ??
              'https://auth.floatplane.com/realms/floatplane/protocol/openid-connect/auth');
      final tokenEndpoint = _useOAuthOverrides
          ? _overrideTokenEndpoint
          : (config?.tokenEndpoint ??
              'https://auth.floatplane.com/realms/floatplane/protocol/openid-connect/token');

      final AuthorizationTokenResponse result =
          await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          clientId,
          _redirectUrl,
          serviceConfiguration: AuthorizationServiceConfiguration(
            authorizationEndpoint: authEndpoint,
            tokenEndpoint: tokenEndpoint,
          ),
          scopes: _scopes,
          promptValues: ['login'],
        ),
      );

      Map<String, dynamic>? userInfo;
      if (result.idToken != null) {
        userInfo = JwtDecoder.decode(result.idToken!);
      }

      return OAuth2Result.success(
        accessToken: result.accessToken!,
        refreshToken: result.refreshToken,
        idToken: result.idToken,
        userInfo: userInfo,
        expirationDateTime: result.accessTokenExpirationDateTime,
      );
    } on PlatformException catch (e) {
      if (e.code == 'authorize_and_exchange_code_failed') {
        return OAuth2Result.cancelled();
      } else {
        return OAuth2Result.error('OAuth2 Error: ${e.message}');
      }
    } catch (e) {
      return OAuth2Result.error('Unexpected error: $e');
    }
  }

  /// Desktop OAuth flow using manual browser launch and local server
  Future<OAuth2Result> _performDesktopAuthFlow({WhiteLabel? whiteLabel}) async {
    // Close any existing server to free the port
    try {
      await server?.close(force: true);
      server = null;
    } catch (_) {
      // Ignore errors when closing
    }

    try {
      final config = await getOpenIDConfig(whiteLabel: whiteLabel);
      final clientId = await getClientId();

      _log.fine('OpenID config: ${config.toString()}');

      // Use overrides if flag enabled, otherwise use dynamic config or Floatplane defaults
      final authEndpoint = _useOAuthOverrides
          ? _overrideAuthEndpoint
          : (config?.authorizationEndpoint ??
              'https://auth.floatplane.com/realms/floatplane/protocol/openid-connect/auth');

      // Generate PKCE parameters
      final String codeVerifier = _generateCodeVerifier();
      final String codeChallenge = _generateCodeChallenge(codeVerifier);
      final String state = _generateState();

      OAuth2Result? result;

      try {
        server?.close();
        server = await HttpServer.bind('localhost', 36479, shared: true);

        // Build authorization URL
        final authUri = Uri.parse(authEndpoint).replace(
          queryParameters: {
            'client_id': clientId,
            'redirect_uri': _redirectUrlDesktop,
            'response_type': 'code',
            'scope': _scopes.join(' '),
            'code_challenge': codeChallenge,
            'code_challenge_method': 'S256',
            'state': state,
            'prompt': 'login',
          },
        );

        // Launch browser
        if (await canLaunchUrl(authUri)) {
          await launchUrl(authUri, mode: LaunchMode.externalApplication);
        } else {
          return OAuth2Result.error('Could not launch browser');
        }

        // Listen for callback
        if (server == null) {
          return OAuth2Result.error('Server failed to start');
        }
        await for (HttpRequest request in server!) {
          if (request.uri.path == '/oauth/callback') {
            final queryParams = request.uri.queryParameters;

            if (queryParams.containsKey('error')) {
              result = OAuth2Result.error(
                  queryParams['error'] ?? 'Authorization failed');
            } else if (queryParams.containsKey('code')) {
              final receivedState = queryParams['state'];

              if (receivedState != state) {
                result = OAuth2Result.error('Invalid state parameter');
              } else {
                // Exchange code for tokens
                result = await _exchangeCodeForTokens(
                  queryParams['code']!,
                  codeVerifier,
                );
              }
            } else {
              result = OAuth2Result.cancelled();
            }

            // Send response to browser
            request.response.statusCode = 200;
            request.response.headers.set('content-type', 'text/html');
            request.response.write('''
              <!DOCTYPE html>
              <html>
                <head>
                  <meta charset="UTF-8">
                  <meta name="viewport" content="width=device-width, initial-scale=1.0">
                  <title>Floaty Authentication</title>
                  <style>
                    * {
                      margin: 0;
                      padding: 0;
                      box-sizing: border-box;
                    }
                    body {
                      font-family: 'Roboto', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
                      background: #121212;
                      min-height: 100vh;
                      display: flex;
                      align-items: center;
                      justify-content: center;
                      animation: fadeIn 0.3s ease-in;
                    }
                    @keyframes fadeIn {
                      from { opacity: 0; }
                      to { opacity: 1; }
                    }
                    .container {
                      background: #1E1E1E;
                      border-radius: 12px;
                      padding: 48px 40px;
                      box-shadow: 0 8px 32px rgba(0, 0, 0, 0.4);
                      text-align: center;
                      max-width: 420px;
                      animation: slideUp 0.4s cubic-bezier(0.4, 0, 0.2, 1);
                    }
                    @keyframes slideUp {
                      from {
                        transform: translateY(20px);
                        opacity: 0;
                      }
                      to {
                        transform: translateY(0);
                        opacity: 1;
                      }
                    }
                    .icon {
                      width: 64px;
                      height: 64px;
                      margin: 0 auto 24px;
                      border-radius: 50%;
                      display: flex;
                      align-items: center;
                      justify-content: center;
                      background: ${result.isSuccess ? '#4CAF50' : '#F44336'};
                      animation: scaleIn 0.3s cubic-bezier(0.34, 1.56, 0.64, 1) 0.1s both;
                    }
                    @keyframes scaleIn {
                      from {
                        transform: scale(0);
                      }
                      to {
                        transform: scale(1);
                      }
                    }
                    .icon svg {
                      width: 32px;
                      height: 32px;
                      stroke: white;
                      stroke-width: 3;
                      fill: none;
                      stroke-linecap: round;
                      stroke-linejoin: round;
                    }
                    h1 {
                      color: #FFFFFF;
                      font-size: 24px;
                      font-weight: 500;
                      margin-bottom: 12px;
                      letter-spacing: 0.25px;
                    }
                    p {
                      color: #B3B3B3;
                      font-size: 14px;
                      line-height: 1.5;
                      margin-bottom: 32px;
                      letter-spacing: 0.25px;
                    }
                    .button {
                      background-color: ${result.isSuccess ? '#4CAF50' : '#F44336'};
                      color: #FFFFFF;
                      border: none;
                      padding: 12px 32px;
                      border-radius: 4px;
                      font-size: 14px;
                      font-weight: 500;
                      text-transform: uppercase;
                      letter-spacing: 1.25px;
                      cursor: pointer;
                      transition: background-color 0.2s ease, box-shadow 0.2s ease;
                      box-shadow: 0 2px 4px rgba(0, 0, 0, 0.3);
                    }
                    .button:hover {
                      background-color: ${result.isSuccess ? '#45A049' : '#E53935'};
                      box-shadow: 0 4px 8px rgba(0, 0, 0, 0.4);
                    }
                    .button:active {
                      background-color: ${result.isSuccess ? '#388E3C' : '#D32F2F'};
                      box-shadow: 0 1px 2px rgba(0, 0, 0, 0.3);
                    }
                    .countdown {
                      color: #757575;
                      font-size: 12px;
                      margin-top: 20px;
                      letter-spacing: 0.4px;
                    }
                    .countdown-timer {
                      color: #9E9E9E;
                      font-weight: 500;
                    }
                  </style>
                </head>
                <body>
                  <div class="container">
                    <div class="icon">
                      ${result.isSuccess ? '''
                        <svg viewBox="0 0 24 24">
                          <polyline points="20 6 9 17 4 12"></polyline>
                        </svg>
                      ''' : '''
                        <svg viewBox="0 0 24 24">
                          <line x1="18" y1="6" x2="6" y2="18"></line>
                          <line x1="6" y1="6" x2="18" y2="18"></line>
                        </svg>
                      '''}
                    </div>
                    <h1>Authentication ${result.isSuccess ? 'Successful' : 'Failed'}</h1>
                    <p>
                      ${result.isSuccess ? 'You have successfully signed in to Floaty. Return to the app to continue.' : 'Authentication could not be completed. Return to the app and try again.'}
                    </p>
                    <div class="countdown">You can close this tab now</div>
                  </div>
                </body>
              </html>
            ''');
            await windowManager.focus();
            await request.response.close();
            break;
          }
        }
      } finally {
        await server?.close(force: true);
        server = null;
      }

      return result ?? OAuth2Result.cancelled();
    } catch (e) {
      return OAuth2Result.error('Desktop OAuth error: $e');
    }
  }

  /// Exchange authorization code for access tokens
  Future<OAuth2Result> _exchangeCodeForTokens(
    String code,
    String codeVerifier,
  ) async {
    try {
      final config = await getOpenIDConfig();
      final clientId = await getClientId();

      // Use overrides if flag enabled, otherwise use dynamic config or Floatplane defaults
      final tokenEndpoint = _useOAuthOverrides
          ? _overrideTokenEndpoint
          : (config?.tokenEndpoint ??
              'https://auth.floatplane.com/realms/floatplane/protocol/openid-connect/token');

      final response = await _dio.post(
        tokenEndpoint,
        data: {
          'grant_type': 'authorization_code',
          'client_id': clientId,
          'code': code,
          'redirect_uri': _currentRedirectUrl,
          'code_verifier': codeVerifier,
        },
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ),
      );

      if (response.statusCode == 200) {
        final tokenData = response.data;
        Map<String, dynamic>? userInfo;

        if (tokenData['id_token'] != null) {
          userInfo = JwtDecoder.decode(tokenData['id_token']);
        }

        return OAuth2Result.success(
          accessToken: tokenData['access_token'],
          refreshToken: tokenData['refresh_token'],
          idToken: tokenData['id_token'],
          userInfo: userInfo,
          expirationDateTime: tokenData['expires_in'] != null
              ? DateTime.now().add(Duration(seconds: tokenData['expires_in']))
              : null,
        );
      } else {
        return OAuth2Result.error(
            'Token exchange failed: ${response.statusCode}');
      }
    } catch (e) {
      return OAuth2Result.error('Token exchange error: $e');
    }
  }

  /// Refreshes the access token using the refresh token
  /// Uses a lock to prevent concurrent refresh operations
  Future<OAuth2Result> refreshToken(String refreshToken) async {
    // Create a key for this specific refresh token
    final refreshKey = refreshToken.hashCode.toString();

    // If there's already a pending refresh operation for this token, wait for it
    if (_pendingRefreshOperations.containsKey(refreshKey)) {
      return _pendingRefreshOperations[refreshKey]!;
    }

    // Create the refresh operation and store it
    final operation = _refreshTokenInternal(refreshToken);
    _pendingRefreshOperations[refreshKey] = operation;

    try {
      final result = await operation;
      return result;
    } finally {
      // Clean up the pending operation
      _pendingRefreshOperations.remove(refreshKey);
    }
  }

  /// Internal implementation of refreshToken without locking
  Future<OAuth2Result> _refreshTokenInternal(String refreshToken) async {
    try {
      if (_canUseAppAuth) {
        return _refreshTokenMobile(refreshToken);
      } else {
        return _refreshTokenDesktop(refreshToken);
      }
    } catch (e) {
      return OAuth2Result.error('Token refresh error: $e');
    }
  }

  Future<OAuth2Result> _refreshTokenMobile(String refreshToken) async {
    final config = await getOpenIDConfig();
    final clientId = await getClientId();

    // Use overrides if flag enabled, otherwise use dynamic config or Floatplane defaults
    final authEndpoint = _useOAuthOverrides
        ? _overrideAuthEndpoint
        : (config?.authorizationEndpoint ??
            'https://auth.floatplane.com/realms/floatplane/protocol/openid-connect/auth');
    final tokenEndpoint = _useOAuthOverrides
        ? _overrideTokenEndpoint
        : (config?.tokenEndpoint ??
            'https://auth.floatplane.com/realms/floatplane/protocol/openid-connect/token');

    final TokenResponse result = await _appAuth.token(
      TokenRequest(
        clientId,
        _redirectUrl,
        refreshToken: refreshToken,
        serviceConfiguration: AuthorizationServiceConfiguration(
          authorizationEndpoint: authEndpoint,
          tokenEndpoint: tokenEndpoint,
        ),
      ),
    );

    Map<String, dynamic>? userInfo;
    if (result.idToken != null) {
      userInfo = JwtDecoder.decode(result.idToken!);
    }

    return OAuth2Result.success(
      accessToken: result.accessToken!,
      refreshToken: result.refreshToken,
      idToken: result.idToken,
      userInfo: userInfo,
      expirationDateTime: result.accessTokenExpirationDateTime,
    );
  }

  Future<OAuth2Result> _refreshTokenDesktop(String refreshToken) async {
    final config = await getOpenIDConfig();
    final clientId = await getClientId();

    // Use overrides if flag enabled, otherwise use dynamic config or Floatplane defaults
    final tokenEndpoint = _useOAuthOverrides
        ? _overrideTokenEndpoint
        : (config?.tokenEndpoint ??
            'https://auth.floatplane.com/realms/floatplane/protocol/openid-connect/token');

    final response = await _dio.post(
      tokenEndpoint,
      data: {
        'grant_type': 'refresh_token',
        'client_id': clientId,
        'refresh_token': refreshToken,
      },
      options: Options(
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      ),
    );

    if (response.statusCode == 200) {
      final tokenData = response.data;
      Map<String, dynamic>? userInfo;

      if (tokenData['id_token'] != null) {
        userInfo = JwtDecoder.decode(tokenData['id_token']);
      }

      return OAuth2Result.success(
        accessToken: tokenData['access_token'],
        refreshToken: tokenData['refresh_token'] ?? refreshToken,
        idToken: tokenData['id_token'],
        userInfo: userInfo,
        expirationDateTime: tokenData['expires_in'] != null
            ? DateTime.now().add(Duration(seconds: tokenData['expires_in']))
            : null,
      );
    } else if (response.statusCode == 400) {
      final whitelabel = await whitelabels.getSelectedWhitelabel();
      // Clear OAuth2 client from cache
      fpApiRequests.clearOAuth2Client(whitelabel.friendlyName);

      // Clear OAuth2 tokens for this whitelabel
      await clearStoredTokens(
        whitelabel: whitelabel.friendlyName,
      );

      // Remove from logged in labels
      await whitelabels.removeLoggedInLabel(whitelabel.friendlyName);

      // Update selected whitelabel if needed
      if ((await whitelabels.getFirstLoggedInLabelOrDefault()).friendlyName ==
          (await settings.getKey('whitelabel'))) {
        rootLayoutKey.currentState?.ref
            .read(mediaPlayerServiceProvider.notifier)
            .changeState(MediaPlayerState.none);
      }

      await settings.setKey('whitelabel',
          (await whitelabels.getFirstLoggedInLabelOrDefault()).friendlyName);
      return OAuth2Result.error('Refresh token is invalid or expired');
    } else {
      return OAuth2Result.error('Token refresh failed: ${response.statusCode}');
    }
  }

  /// Logs out by revoking tokens and clearing session
  Future<bool> revoke(String? accessToken) async {
    try {
      if (accessToken != null) {
        final config = await getOpenIDConfig();
        final clientId = await getClientId();

        // Use overrides if flag enabled, otherwise use dynamic config or Floatplane defaults
        final revocationEndpoint = _useOAuthOverrides
            ? _overrideRevocationEndpoint
            : (config?.revocationEndpoint ??
                'https://auth.floatplane.com/realms/floatplane/protocol/openid-connect/revoke');

        // Try to revoke the token
        await _dio.post(
          revocationEndpoint,
          data: {
            'client_id': clientId,
            'token': accessToken,
          },
          options: Options(
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
            },
          ),
        );
      }

      // Clear stored tokens
      await clearStoredTokens();

      return true;
    } catch (e) {
      if (kDebugMode) {
        _log.severe('Logout error: $e');
      }
      return false;
    }
  }

  /// Store tokens securely with whitelabel support
  Future<void> storeTokens(OAuth2Result result, {String? whitelabel}) async {
    if (result.isSuccess) {
      final whitelabelPrefix = whitelabel ?? 'default';

      await settings.setKey(
          '${whitelabelPrefix}_oauth2_access_token', result.accessToken ?? '');

      await settings.setKey('${whitelabelPrefix}_oauth2_refresh_token',
          result.refreshToken ?? '');

      await settings.setKey(
          '${whitelabelPrefix}_oauth2_id_token', result.idToken ?? '');
      if (result.expirationDateTime != null) {
        await settings.setKey('${whitelabelPrefix}_oauth2_expiration',
            result.expirationDateTime!.toIso8601String());
      }
      if (result.userInfo != null) {
        await settings.setKey('${whitelabelPrefix}_oauth2_user_info',
            jsonEncode(result.userInfo));
      }

      // Mark this whitelabel as using OAuth2
      await settings.setKey('${whitelabelPrefix}_auth_method', 'oauth2');
    }
  }

  /// Get stored access token for a specific whitelabel
  /// Automatically refreshes the token if it's expired or about to expire
  /// Uses a lock to prevent concurrent token operations
  Future<String?> getAccessToken({String? whitelabel}) async {
    final whitelabelPrefix = whitelabel ?? 'default';

    // If there's already a pending token operation for this whitelabel, wait for it
    if (_pendingTokenOperations.containsKey(whitelabelPrefix)) {
      return _pendingTokenOperations[whitelabelPrefix];
    }

    // Create the token operation and store it
    final operation = _getAccessTokenInternal(whitelabel: whitelabel);
    _pendingTokenOperations[whitelabelPrefix] = operation;

    try {
      final result = await operation;
      return result;
    } finally {
      // Clean up the pending operation
      _pendingTokenOperations.remove(whitelabelPrefix);
    }
  }

  /// Internal implementation of getAccessToken without locking
  Future<String?> _getAccessTokenInternal({String? whitelabel}) async {
    final whitelabelPrefix = whitelabel ?? 'default';
    final key = '${whitelabelPrefix}_oauth2_access_token';
    final token = await settings.getKey(key);

    if (token.isEmpty) {
      return null;
    }

    // Check if token is expired and try to refresh
    final expired = await isTokenExpired(whitelabel: whitelabel);
    if (expired) {
      final refreshTokenStr = await getRefreshToken(whitelabel: whitelabel);
      if (refreshTokenStr != null) {
        final result = await refreshToken(refreshTokenStr);
        if (result.isSuccess) {
          await storeTokens(result, whitelabel: whitelabel);
          return result.accessToken;
        }
      }
      // Token expired and refresh failed
      return null;
    }

    return token;
  }

  /// Get stored refresh token for a specific whitelabel
  Future<String?> getRefreshToken({String? whitelabel}) async {
    final whitelabelPrefix = whitelabel ?? 'default';
    final token =
        await settings.getKey('${whitelabelPrefix}_oauth2_refresh_token');
    return token.isEmpty ? null : token;
  }

  /// Get stored token expiration for a specific whitelabel
  Future<String?> getExpiration({String? whitelabel}) async {
    final whitelabelPrefix = whitelabel ?? 'default';
    final expiration =
        await settings.getKey('${whitelabelPrefix}_oauth2_expiration');
    return expiration.isEmpty ? null : expiration;
  }

  /// Get stored user info for a specific whitelabel
  Future<Map<String, dynamic>?> getStoredUserInfo({String? whitelabel}) async {
    final whitelabelPrefix = whitelabel ?? 'default';
    final userInfoJson =
        await settings.getKey('${whitelabelPrefix}_oauth2_user_info');
    if (userInfoJson.isEmpty) return null;
    return jsonDecode(userInfoJson) as Map<String, dynamic>;
  }

  /// Check if token is expired for a specific whitelabel
  Future<bool> isTokenExpired({String? whitelabel}) async {
    final whitelabelPrefix = whitelabel ?? 'default';
    final key = '${whitelabelPrefix}_oauth2_expiration';
    final expirationStr = await settings.getKey(key);

    if (expirationStr.isEmpty) {
      return false;
    }

    final expiration = DateTime.parse(expirationStr);
    final now = DateTime.now();
    final expirationWithBuffer =
        expiration.subtract(const Duration(minutes: 5));
    final isExpired = now.isAfter(expirationWithBuffer);

    return isExpired;
  }

  /// Check if user is authenticated for a specific whitelabel
  Future<bool> isAuthenticated({String? whitelabel}) async {
    // Use the same locking mechanism through getAccessToken
    // to prevent duplicate refresh operations
    final token = await getAccessToken(whitelabel: whitelabel);
    if (token == null) {
      return false;
    }

    // Token was successfully retrieved (either from cache or after refresh)
    return true;
  }

  /// Clear all stored tokens for a specific whitelabel
  Future<void> clearStoredTokens({String? whitelabel}) async {
    final whitelabelPrefix = whitelabel ?? 'default';
    await settings.removeKey('${whitelabelPrefix}_oauth2_access_token');
    await settings.removeKey('${whitelabelPrefix}_oauth2_refresh_token');
    await settings.removeKey('${whitelabelPrefix}_oauth2_id_token');
    await settings.removeKey('${whitelabelPrefix}_oauth2_expiration');
    await settings.removeKey('${whitelabelPrefix}_oauth2_user_info');
    await settings.removeKey('${whitelabelPrefix}_auth_method');
  }

  /// Check if tokens are stored (regardless of whether they're expired)
  Future<bool> hasStoredTokens({String? whitelabel}) async {
    final whitelabelPrefix = whitelabel ?? 'default';
    final accessToken =
        await settings.getKey('${whitelabelPrefix}_oauth2_access_token');
    final refreshToken =
        await settings.getKey('${whitelabelPrefix}_oauth2_refresh_token');
    return accessToken.isNotEmpty || refreshToken.isNotEmpty;
  }

  /// Get the auth method for a whitelabel (oauth2, cookie, or null if not set)
  Future<String?> getAuthMethod({String? whitelabel}) async {
    final whitelabelPrefix = whitelabel ?? 'default';
    final key = '${whitelabelPrefix}_auth_method';
    final method = await settings.getKey(key);
    _log.fine('Auth method for $whitelabelPrefix: $method');
    return method.isEmpty ? null : method;
  }

  /// Set the auth method for a whitelabel
  Future<void> setAuthMethod(String method, {String? whitelabel}) async {
    final whitelabelPrefix = whitelabel ?? 'default';
    await settings.setKey('${whitelabelPrefix}_auth_method', method);
  }

  /// Gets headers for non fpapi requests
  Future<Map<String, String>> getAuthHeaders(
      String whitelabelFriendlyName) async {
    final headers = <String, String>{};
    final whitelabel = whitelabels.getWhitelabel(whitelabelFriendlyName);
    final method = await getAuthMethod(whitelabel: whitelabelFriendlyName);

    if (method == 'oauth2') {
      final accessToken =
          await getAccessToken(whitelabel: whitelabelFriendlyName);
      if (accessToken != null) {
        headers['Authorization'] = 'Bearer $accessToken';
      }
    } else if (method == 'cookie') {
      settings
          .getAuthTokenFromCookieJar(
              whitelabelFriendlyName: whitelabelFriendlyName)
          .then((cookieToken) {
        if (cookieToken != null) {
          headers['cookie'] = '${whitelabel.cookieName}=$cookieToken';
        }
      });
    }

    return headers;
  }

  /// Generates a cryptographically secure code verifier for PKCE
  String _generateCodeVerifier() {
    final random = Random.secure();
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = random.nextInt(256);
    }
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Generates code challenge from code verifier using SHA256
  String _generateCodeChallenge(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// Generates a random state parameter for CSRF protection
  String _generateState() {
    final random = Random.secure();
    final bytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      bytes[i] = random.nextInt(256);
    }
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Fetches additional user information from the userinfo endpoint
  Future<Map<String, dynamic>?> fetchUserInfo(String accessToken) async {
    try {
      final config = await getOpenIDConfig();

      // Use overrides if flag enabled, otherwise use dynamic config or Floatplane defaults
      final userinfoEndpoint = _useOAuthOverrides
          ? _overrideUserinfoEndpoint
          : (config?.userinfoEndpoint ??
              'https://auth.floatplane.com/realms/floatplane/protocol/openid-connect/userinfo');

      final response = await _dio.get(
        userinfoEndpoint,
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
          },
        ),
      );

      if (response.statusCode == 200) {
        return response.data;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        _log.warning('Failed to fetch user info: $e');
      }
      return null;
    }
  }
}

/// Result class for OAuth2 operations
class OAuth2Result {
  final bool isSuccess;
  final bool isCancelled;
  final String? error;
  final String? accessToken;
  final String? refreshToken;
  final String? idToken;
  final Map<String, dynamic>? userInfo;
  final DateTime? expirationDateTime;

  OAuth2Result._({
    required this.isSuccess,
    required this.isCancelled,
    this.error,
    this.accessToken,
    this.refreshToken,
    this.idToken,
    this.userInfo,
    this.expirationDateTime,
  });

  factory OAuth2Result.success({
    required String accessToken,
    String? refreshToken,
    String? idToken,
    Map<String, dynamic>? userInfo,
    DateTime? expirationDateTime,
  }) {
    return OAuth2Result._(
      isSuccess: true,
      isCancelled: false,
      accessToken: accessToken,
      refreshToken: refreshToken,
      idToken: idToken,
      userInfo: userInfo,
      expirationDateTime: expirationDateTime,
    );
  }

  factory OAuth2Result.cancelled() {
    return OAuth2Result._(
      isSuccess: false,
      isCancelled: true,
    );
  }

  factory OAuth2Result.error(String error) {
    return OAuth2Result._(
      isSuccess: false,
      isCancelled: false,
      error: error,
    );
  }

  /// Returns the username from user info (preferred_username or email)
  String? get username {
    if (userInfo != null) {
      return userInfo!['preferred_username'] ?? userInfo!['email'];
    }
    return null;
  }

  /// Returns the user's email from user info
  String? get email {
    return userInfo?['email'];
  }

  /// Returns the user's name from user info
  String? get name {
    return userInfo?['name'] ?? userInfo?['preferred_username'];
  }

  /// Checks if the token is expired or will expire soon
  bool get isTokenExpired {
    if (expirationDateTime == null) return false;
    return DateTime.now()
        .isAfter(expirationDateTime!.subtract(const Duration(minutes: 5)));
  }
}
