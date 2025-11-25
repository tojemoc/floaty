import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:floaty/settings.dart';
import 'package:floaty/whitelabels.dart';

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
      responseTypesSupported: List<String>.from(json['response_types_supported'] ?? []),
      grantTypesSupported: List<String>.from(json['grant_types_supported'] ?? []),
    );
  }
}

class OAuth2Service {
  static const FlutterAppAuth _appAuth = FlutterAppAuth();
  

  // feat flag for oauth overrides
  static const bool _useOAuthOverrides = bool.fromEnvironment('USE_OAUTH_OVERRIDES', defaultValue: false);
  static const String _overrideClientId = String.fromEnvironment('OAUTH_CLIENT_ID');
  static const String _overrideAuthEndpoint = String.fromEnvironment('OAUTH_AUTH_ENDPOINT');
  static const String _overrideTokenEndpoint = String.fromEnvironment('OAUTH_TOKEN_ENDPOINT');
  static const String _overrideUserinfoEndpoint = String.fromEnvironment('OAUTH_USERINFO_ENDPOINT');
  static const String _overrideRevocationEndpoint = String.fromEnvironment('OAUTH_REVOCATION_ENDPOINT');
  
  // generic defaults incase something breaks
  static const String _defaultClientId = 'floaty';
  static const String _redirectUrl = 'uk.bw86.floaty://oauth/callback';
  static const String _redirectUrlDesktop = 'http://localhost:36479/oauth/callback';
  static const List<String> _scopes = ['openid', 'profile', 'email', 'user.read', 'offline_access'];

  final Dio _dio;
  OpenIDConfig? _cachedConfig;
  String? _cachedConfigUrl;

  OAuth2Service({Dio? dio}) : _dio = dio ?? Dio();

  /// Get the client ID - uses override if flag is enabled, otherwise defaults to hydravion
  Future<String> getClientId() async {
    if (_useOAuthOverrides) {
      return _overrideClientId;
    }
    return _defaultClientId;
  }

  /// Fetches OpenID Connect Discovery configuration from the whitelabel
  /// Returns null if config URL is not available (will use fallback defaults)
  Future<OpenIDConfig?> getOpenIDConfig() async {
    // If using overrides, skip dynamic config fetching
    if (_useOAuthOverrides) {
      return null;
    }
    
    try {
      final whitelabel = await whitelabels.getSelectedWhitelabel();
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
  Future<OAuth2Result> login() async {
    try {
      // Try to fetch OpenID configuration (optional)
      await getOpenIDConfig();
      
      if (_canUseAppAuth) {
        return _performMobileAuthFlow();
      } else {
        return _performDesktopAuthFlow();
      }
    } catch (e) {
      return OAuth2Result.error('Login failed: $e');
    }
  }

  /// Mobile OAuth flow using flutter_appauth
  Future<OAuth2Result> _performMobileAuthFlow() async {
    try {
      final config = await getOpenIDConfig();
      final clientId = await getClientId();
      
      // Use overrides if flag enabled, otherwise use dynamic config or Floatplane defaults
      final authEndpoint = _useOAuthOverrides ? _overrideAuthEndpoint : 
          (config?.authorizationEndpoint ?? 
          'https://auth.floatplane.com/realms/floatplane/protocol/openid-connect/auth');
      final tokenEndpoint = _useOAuthOverrides ? _overrideTokenEndpoint : 
          (config?.tokenEndpoint ?? 
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
  Future<OAuth2Result> _performDesktopAuthFlow() async {
    try {
      final config = await getOpenIDConfig();
      final clientId = await getClientId();
      
      // Use overrides if flag enabled, otherwise use dynamic config or Floatplane defaults
      final authEndpoint = _useOAuthOverrides ? _overrideAuthEndpoint : 
          (config?.authorizationEndpoint ?? 
          'https://auth.floatplane.com/realms/floatplane/protocol/openid-connect/auth');
      
      // Generate PKCE parameters
      final String codeVerifier = _generateCodeVerifier();
      final String codeChallenge = _generateCodeChallenge(codeVerifier);
      final String state = _generateState();

      // Start local server to listen for callback
      late HttpServer server;
      OAuth2Result? result;

      try {
        server = await HttpServer.bind('localhost', 36479);
        
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
        await for (HttpRequest request in server) {
          
          if (request.uri.path == '/oauth/callback') {
            final queryParams = request.uri.queryParameters;

            if (queryParams.containsKey('error')) {
              result = OAuth2Result.error(queryParams['error'] ?? 'Authorization failed');
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
                <head><title>Floaty Authentication</title></head>
                <body>
                  <h1>Authentication ${result.isSuccess ? 'Successful' : 'Failed'}</h1>
                  <p>You can now close this window and return to Floaty.</p>
                  <script>window.close();</script>
                </body>
              </html>
            ''');
            await request.response.close();
            break;
          }
        }
      } finally {
        await server.close();
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
      final tokenEndpoint = _useOAuthOverrides ? _overrideTokenEndpoint : 
          (config?.tokenEndpoint ?? 
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
        return OAuth2Result.error('Token exchange failed: ${response.statusCode}');
      }
    } catch (e) {
      return OAuth2Result.error('Token exchange error: $e');
    }
  }

  /// Refreshes the access token using the refresh token
  Future<OAuth2Result> refreshToken(String refreshToken) async {
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
    final authEndpoint = _useOAuthOverrides ? _overrideAuthEndpoint : 
        (config?.authorizationEndpoint ?? 
        'https://auth.floatplane.com/realms/floatplane/protocol/openid-connect/auth');
    final tokenEndpoint = _useOAuthOverrides ? _overrideTokenEndpoint : 
        (config?.tokenEndpoint ?? 
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
    final tokenEndpoint = _useOAuthOverrides ? _overrideTokenEndpoint : 
        (config?.tokenEndpoint ?? 
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
    } else {
      return OAuth2Result.error('Token refresh failed: ${response.statusCode}');
    }
  }

  /// Logs out by revoking tokens and clearing session
  Future<bool> logout(String? accessToken) async {
    try {
      if (accessToken != null) {
        final config = await getOpenIDConfig();
        final clientId = await getClientId();
        
        // Use overrides if flag enabled, otherwise use dynamic config or Floatplane defaults
        final revocationEndpoint = _useOAuthOverrides ? _overrideRevocationEndpoint : 
            (config?.revocationEndpoint ?? 
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
        print('Logout error: $e');
      }
      return false;
    }
  }

  /// Store tokens securely with whitelabel support
  Future<void> storeTokens(OAuth2Result result, {String? whitelabel}) async {
    if (result.isSuccess) {
      final whitelabelPrefix = whitelabel ?? 'default';
      
      await settings.setKey('${whitelabelPrefix}_oauth2_access_token', result.accessToken ?? '');
      
      await settings.setKey('${whitelabelPrefix}_oauth2_refresh_token', result.refreshToken ?? '');
      
      await settings.setKey('${whitelabelPrefix}_oauth2_id_token', result.idToken ?? '');
      if (result.expirationDateTime != null) {
        await settings.setKey('${whitelabelPrefix}_oauth2_expiration', result.expirationDateTime!.toIso8601String());
      }
      if (result.userInfo != null) {
        await settings.setKey('${whitelabelPrefix}_oauth2_user_info', jsonEncode(result.userInfo));
      }
      
      // Mark this whitelabel as using OAuth2
      await settings.setKey('${whitelabelPrefix}_auth_method', 'oauth2');
    }
  }

  /// Get stored access token for a specific whitelabel
  Future<String?> getAccessToken({String? whitelabel}) async {
    final whitelabelPrefix = whitelabel ?? 'default';
    final token = await settings.getKey('${whitelabelPrefix}_oauth2_access_token');
    return token.isEmpty ? null : token;
  }

  /// Get stored refresh token for a specific whitelabel
  Future<String?> getRefreshToken({String? whitelabel}) async {
    final whitelabelPrefix = whitelabel ?? 'default';
    final token = await settings.getKey('${whitelabelPrefix}_oauth2_refresh_token');
    return token.isEmpty ? null : token;
  }

  /// Get stored token expiration for a specific whitelabel
  Future<String?> getExpiration({String? whitelabel}) async {
    final whitelabelPrefix = whitelabel ?? 'default';
    final expiration = await settings.getKey('${whitelabelPrefix}_oauth2_expiration');
    return expiration.isEmpty ? null : expiration;
  }

  /// Get stored user info for a specific whitelabel
  Future<Map<String, dynamic>?> getStoredUserInfo({String? whitelabel}) async {
    final whitelabelPrefix = whitelabel ?? 'default';
    final userInfoJson = await settings.getKey('${whitelabelPrefix}_oauth2_user_info');
    if (userInfoJson.isEmpty) return null;
    return jsonDecode(userInfoJson) as Map<String, dynamic>;
  }

  /// Check if token is expired for a specific whitelabel
  Future<bool> isTokenExpired({String? whitelabel}) async {
    final whitelabelPrefix = whitelabel ?? 'default';
    final expirationStr = await settings.getKey('${whitelabelPrefix}_oauth2_expiration');
    if (expirationStr.isEmpty) return false;
    
    final expiration = DateTime.parse(expirationStr);
    return DateTime.now().isAfter(expiration.subtract(const Duration(minutes: 5)));
  }

  /// Check if user is authenticated for a specific whitelabel
  Future<bool> isAuthenticated({String? whitelabel}) async {
    
    final token = await getAccessToken(whitelabel: whitelabel);
    if (token == null) {
      return false;
    }
    
    final expired = await isTokenExpired(whitelabel: whitelabel);
    
    if (expired) {
      // Try to refresh token
      final refreshTokenStr = await getRefreshToken(whitelabel: whitelabel);
      if (refreshTokenStr != null) {
        final result = await refreshToken(refreshTokenStr);
        if (result.isSuccess) {
          await storeTokens(result, whitelabel: whitelabel);
          return true;
        }
      }
      return false;
    }

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
  
  /// Get the auth method for a whitelabel (oauth2, cookie, or null if not set)
  Future<String?> getAuthMethod({String? whitelabel}) async {
    final whitelabelPrefix = whitelabel ?? 'default';
    final method = await settings.getKey('${whitelabelPrefix}_auth_method');
    return method.isEmpty ? null : method;
  }
  
  /// Set the auth method for a whitelabel
  Future<void> setAuthMethod(String method, {String? whitelabel}) async {
    final whitelabelPrefix = whitelabel ?? 'default';
    await settings.setKey('${whitelabelPrefix}_auth_method', method);
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
      final userinfoEndpoint = _useOAuthOverrides ? _overrideUserinfoEndpoint : 
          (config?.userinfoEndpoint ?? 
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
        print('Failed to fetch user info: $e');
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
    return DateTime.now().isAfter(expirationDateTime!.subtract(const Duration(minutes: 5)));
  }
}
