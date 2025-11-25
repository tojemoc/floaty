import 'package:floaty/whitelabels.dart';
import 'package:floaty/features/api/models/definitions.dart';
import 'package:floaty/features/logs/repositories/log_service.dart';
import 'package:floaty/features/authentication/services/oauth2_service.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:get_it/get_it.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:http/http.dart' as http;

final FPApiRequests fpApiRequests = GetIt.I<FPApiRequests>();

/// Custom HTTP client wrapper that adds cookie support to oauth2 Client
class _CookieHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final PersistCookieJar cookieJar;

  _CookieHttpClient(this.cookieJar);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Add cookies from jar to request
    final uri = request.url;
    final cookies = await cookieJar.loadForRequest(uri);
    if (cookies.isNotEmpty) {
      final cookieHeader = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      request.headers['cookie'] = cookieHeader;
    }

    // Send request
    final response = await _inner.send(request);

    // Save cookies from response
    final setCookieHeaders = response.headers['set-cookie'];
    if (setCookieHeaders != null) {
      final responseCookies = setCookieHeaders
          .split(',')
          .map((str) => Cookie.fromSetCookieValue(str))
          .toList();
      await cookieJar.saveFromResponse(uri, responseCookies);
    }

    return response;
  }

  @override
  void close() {
    _inner.close();
  }
}

class FPApiRequests {
  String userAgent = 'FloatyClient/error, CFNetwork';
  late final PersistCookieJar cookieJar;
  late final OAuth2Service _oauth2Service;
  final Map<String, oauth2.Client> _oauth2Clients = {};
  late final http.Client _fallbackClient;
  PackageInfo? packageInfo;
  
  // Feature flag for cookie-based testing
  bool get useCookieAuth => const bool.fromEnvironment('USE_COOKIE_AUTH', defaultValue: false);
  
  /// Get the appropriate HTTP client for a specific whitelabel
  Future<http.Client> getHttpClient(String whitelabel) async {
    final authMethod = await _oauth2Service.getAuthMethod(whitelabel: whitelabel);
    final useCookie = (authMethod == 'cookie') || (authMethod == null && useCookieAuth);
    
    if (!useCookie) {
      // Try to get or create OAuth2 client for this whitelabel
      if (!_oauth2Clients.containsKey(whitelabel)) {
        final client = await createOAuth2Client(whitelabel: whitelabel);
        if (client != null) {
          _oauth2Clients[whitelabel] = client;
        }
      }
      
      if (_oauth2Clients.containsKey(whitelabel)) {
        return _oauth2Clients[whitelabel]!;
      }
    }
    
    // Fallback to cookie client
    return _fallbackClient;
  }
  
  /// Get the appropriate HTTP client (OAuth2 or fallback with cookies)
  /// This is kept for backwards compatibility but deprecated
  @Deprecated('Use getHttpClient(whitelabel) instead')
  http.Client get httpClient => _fallbackClient;

  FPApiRequests() {
    _init();
  }

  Future<void> _init() async {
    packageInfo = await PackageInfo.fromPlatform();
    const flavor =
        String.fromEnvironment('FLUTTER_FLAVOR', defaultValue: 'release');
    userAgent =
        'FloatyClient/${packageInfo?.version}+${packageInfo?.buildNumber}-$flavor, CFNetwork';
    final dir = await getApplicationSupportDirectory();
    
    _oauth2Service = OAuth2Service();
    
    cookieJar = PersistCookieJar(
      storage: FileStorage('${dir.path}/.cookies/'),
    );
    
    // Create fallback HTTP client with cookie support
    _fallbackClient = _CookieHttpClient(cookieJar);
    
    // Initialize OAuth2 clients for all logged-in whitelabels
    if (!useCookieAuth) {
      _initOAuth2Clients();
    }
  }
  
  /// Initialize OAuth2 Clients for all logged-in whitelabels
  Future<void> _initOAuth2Clients() async {
    final loggedInLabels = await whitelabels.getLoggedInLabels();
    for (final label in loggedInLabels) {
      final whitelabelName = label.split('-')[0];
      final authMethod = await _oauth2Service.getAuthMethod(whitelabel: whitelabelName);
      if (authMethod == 'oauth2') {
        final client = await createOAuth2Client(whitelabel: whitelabelName);
        if (client != null) {
          _oauth2Clients[whitelabelName] = client;
        }
      }
    }
  }
  
  /// Create or recreate OAuth2 client from stored credentials for a specific whitelabel
  Future<oauth2.Client?> createOAuth2Client({String? whitelabel}) async {
    try {
      final whitelabelName = whitelabel ?? 'default';
      final accessToken = await _oauth2Service.getAccessToken(whitelabel: whitelabelName);
      final refreshToken = await _oauth2Service.getRefreshToken(whitelabel: whitelabelName);
      final expirationStr = await _oauth2Service.getExpiration(whitelabel: whitelabelName);
      
      if (accessToken == null || refreshToken == null) {
        return null;
      }
      
      DateTime? expiration;
      if (expirationStr != null && expirationStr.isNotEmpty) {
        expiration = DateTime.parse(expirationStr);
      }
      
      // Get token endpoint from config or use default
      final config = await _oauth2Service.getOpenIDConfig();
      final tokenEndpoint = config?.tokenEndpoint ?? 
          'https://auth.floatplane.com/realms/floatplane/protocol/openid-connect/token';
      
      final credentials = oauth2.Credentials(
        accessToken,
        refreshToken: refreshToken,
        tokenEndpoint: Uri.parse(tokenEndpoint),
        expiration: expiration,
      );
      
      // Create a custom HTTP client that includes cookies
      final innerClient = _CookieHttpClient(cookieJar);
      
      final client = oauth2.Client(
        credentials,
        identifier: await _oauth2Service.getClientId(),
        onCredentialsRefreshed: (newCredentials) async {
          // Save refreshed tokens back to storage for this whitelabel
          await _oauth2Service.storeTokens(
            OAuth2Result.success(
              accessToken: newCredentials.accessToken,
              refreshToken: newCredentials.refreshToken,
              expirationDateTime: newCredentials.expiration,
            ),
            whitelabel: whitelabelName,
          );
        },
        httpClient: innerClient,
      );
      
      return client;
    } catch (e) {
      return null;
    }
  }
  
  /// Remove OAuth2 client from cache (e.g., on logout)
  void clearOAuth2Client(String whitelabel) {
    if (_oauth2Clients.containsKey(whitelabel)) {
        _oauth2Clients[whitelabel]?.close();
      _oauth2Clients.remove(whitelabel);
    }
  }

  Future<String> postData(
    String apiUrl,
    String whitelabel, [
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParams,
  ]) async {
    try {
      final whiteLabel = whitelabels.getWhitelabel(whitelabel);
      final client = await getHttpClient(whiteLabel.friendlyName);
      
      var url = Uri.parse('${whiteLabel.apiUrl}/$apiUrl');
      if (queryParams != null && queryParams.isNotEmpty) {
        url = url.replace(queryParameters: queryParams);
      }
      
      final response = await client.post(
        url,
        headers: {'Content-Type': 'application/json', 'User-Agent': userAgent},
        body: body != null ? jsonEncode(body) : null,
      );
      return response.body;
    } catch (e) {
      return 'Error: $e';
    }
  }

  Future<dynamic> fetchData(
    String apiUrl,
    String whitelabel, [
    Map<String, dynamic>? queryParams,
  ]) async {
    try {
      final whiteLabel = whitelabels.getWhitelabel(whitelabel);
      final client = await getHttpClient(whiteLabel.friendlyName);
      
      var url = Uri.parse('${whiteLabel.apiUrl}/$apiUrl');
      if (queryParams != null && queryParams.isNotEmpty) {
        url = url.replace(queryParameters: queryParams);
      }
      
      final response = await client.get(
        url,
        headers: {'User-Agent': userAgent},
      );
      return response.body;
    } catch (e) {
      return {'statusCode': 500, 'body': e.toString()};
    }
  }

  Stream<UserSelfV3Response> getUser(String whitelabel) async* {
    try {
      final user = await fetchData('v3/user/self', whitelabel);
      if (user != null && user is String && user.isNotEmpty) {
        yield UserSelfV3Response.fromJson(jsonDecode(user));
      }
    } catch (e) {
      yield UserSelfV3Response();
    }
  }

  Future<UserSelfV3Response> getUserNOS(String whitelabel) async {
    try {
      final user = await fetchData('v3/user/self', whitelabel);
      return UserSelfV3Response.fromJson(jsonDecode(user));
    } catch (e) {
      return UserSelfV3Response();
    }
  }

  Future<List<dynamic>> getNamedUser(String whitelabel, String username) async {
    final user =
        await fetchData('v3/user/named?username[0]=$username', whitelabel);
    if (user != null && user.isNotEmpty) {
      return jsonDecode(user);
    }
    return [];
  }

  Future<dynamic> getActivity(String whitelabel, String userId) async {
    final activity = await fetchData('v3/user/activity?id=$userId', whitelabel);
    if (activity != null && activity.isNotEmpty) {
      return activity;
    }
    return [];
  }

  Future<dynamic> registerNotifications(String whitelabel, String token) async {
    final response =
        await postData('v3/push/web/register?token=$token', whitelabel);
    LogService.logInfo('✅ Notifications registered! Response: $response');
    return response;
  }

  Stream<List<CreatorModelV3>> getSubscribedCreators(String whitelabel) async* {
    try {
      final subres =
          await fetchData('v3/user/subscriptions?active=true', whitelabel);
      if (subres != null && subres is String && subres.isNotEmpty) {
        List<dynamic> subscriptions = jsonDecode(subres);
        List<String> creatorIds = subscriptions
            .where((subscription) =>
                subscription is Map<String, dynamic> &&
                subscription['creator'] is String)
            .map((subscription) => subscription['creator'] as String)
            .toSet() // Remove duplicates
            .toList();
        List<CreatorModelV3> creators = [];
        for (String id in creatorIds) {
          try {
            final creatorInfo =
                await fetchData('v3/creator/info?id=$id', whitelabel);
            if (creatorInfo != null &&
                creatorInfo is String &&
                creatorInfo.isNotEmpty) {
              Map<String, dynamic> creatorJson = jsonDecode(creatorInfo);
              creators.add(CreatorModelV3.fromJson(creatorJson));
            }
          } catch (e) {
            continue;
          }
        }
        yield creators;
      }
    } catch (e) {
      yield [];
    }
  }

  Stream<List<String>> getSubscribedCreatorsIds(String whitelabel) async* {
    try {
      final subres =
          await fetchData('v3/user/subscriptions?active=true', whitelabel);
      if (subres != null && subres.isNotEmpty) {
        List<dynamic> subscriptions = jsonDecode(subres);
        List<String> creatorIds = subscriptions
            .where((subscription) =>
                subscription is Map<String, dynamic> &&
                subscription['creator'] is String)
            .map((subscription) => subscription['creator'] as String)
            .toList();
        yield creatorIds;
      }
    } catch (e) {
      yield [];
    }
  }

  Future<ContentCreatorListV3Response> getMultiCreatorVideoFeed(
      String whitelabel, List<String> creatorIds, int limit,
      {List<ContentCreatorListLastItems>? lastElements}) async {
    try {
      if (creatorIds.isEmpty) {
        return ContentCreatorListV3Response(blogPosts: [], lastElements: []);
      }

      final Map<String, dynamic> queryParams = {
        for (int i = 0; i < creatorIds.length; i++) 'ids[$i]': creatorIds[i],
        'limit': limit.toString(),
      };

      if (lastElements != null && lastElements.isNotEmpty) {
        for (int i = 0; i < lastElements.length; i++) {
          queryParams['fetchAfter[$i][creatorId]'] = lastElements[i].creatorId;
          queryParams['fetchAfter[$i][blogPostId]'] =
              lastElements[i].blogPostId;
          queryParams['fetchAfter[$i][moreFetchable]'] =
              lastElements[i].moreFetchable.toString();
        }
      }

      final response =
          await fetchData('v3/content/creator/list', whitelabel, queryParams);
      if (response != null && response.isNotEmpty) {
        return ContentCreatorListV3Response.fromJson(jsonDecode(response));
      }
      return ContentCreatorListV3Response(blogPosts: [], lastElements: []);
    } catch (error) {
      return ContentCreatorListV3Response(blogPosts: [], lastElements: []);
    }
  }

  Future<List<BlogPostModelV3>> getChannelVideoFeed(
    String whitelabel,
    String creator,
    int limit,
    int fetchAfter, {
    String? channel,
    String? searchQuery,
    Set<String>? contentTypes,
    RangeValues? durationRange,
    DateTime? fromDate,
    DateTime? toDate,
    bool? isAscending,
  }) async {
    try {
      bool? hasVideo = contentTypes?.contains('Video');
      bool? hasAudio = contentTypes?.contains('Audio');
      bool? hasPicture = contentTypes?.contains('Picture');
      bool? hasText = contentTypes?.contains('Text');

      final Map<String, dynamic> queryParams = {
        'id': creator,
        'limit': limit.toString(),
        'fetchAfter': fetchAfter.toString(),
        if (channel != null) 'channel': channel,
        if (fromDate != null) 'fromDate': fromDate.toUtc().toIso8601String(),
        if (toDate != null) 'toDate': toDate.toUtc().toIso8601String(),
        if (contentTypes != null) ...{
          'hasVideo': hasVideo.toString(),
          'hasAudio': hasAudio.toString(),
          'hasPicture': hasPicture.toString(),
          'hasText': hasText.toString(),
        },
        if (durationRange != null) ...{
          if ((durationRange.start * 60).round().toString() != '0')
            'fromDuration': (durationRange.start * 60).round().toString(),
          if ((durationRange.end * 60).round().toString() != '10800')
            'toDuration': (durationRange.end * 60).round().toString(),
        },
        if (isAscending != null) 'sort': isAscending ? 'ASC' : 'DESC',
        if (searchQuery != null && searchQuery.isNotEmpty)
          'search': searchQuery,
      };

      final response =
          await fetchData('v3/content/creator', whitelabel, queryParams);
      if (response != null && response.isNotEmpty) {
        List<dynamic> decodedResponse = jsonDecode(response);
        return decodedResponse
            .map((item) => BlogPostModelV3.fromJson(item))
            .toList();
      }
      return [];
    } catch (error) {
      return [];
    }
  }

  Future<List<GetProgressResponse>> getVideoProgress(
    String whitelabel,
    List<String> blogPostIds,
  ) async {
    final Map<String, dynamic> requestBody = {
      "ids": blogPostIds,
      "contentType": "blogPost"
    };

    try {
      final response =
          await postData('v3/content/get/progress', whitelabel, requestBody);
      if (response.isNotEmpty) {
        final List<dynamic> jsonResponse = jsonDecode(response);
        return jsonResponse
            .map((data) => GetProgressResponse.fromJson(data))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Stream<List<CreatorModelV3>> getCreators(String whitelabel,
      {String? query}) async* {
    try {
      final apiUrl =
          query != null ? 'v3/creator/list?search=$query' : 'v3/creator/list';

      final subres = await fetchData(apiUrl, whitelabel);
      if (subres != null && subres.isNotEmpty) {
        List<dynamic> jsonList = jsonDecode(subres);
        yield jsonList.map((json) => CreatorModelV3.fromJson(json)).toList();
      }
    } catch (e) {
      yield [];
    }
  }

  Stream<List<CreatorDiscoveryResponse>> getCreatorDiscovery(String whitelabel,
      {String? query}) async* {
    try {
      final apiUrl = query != null
          ? 'v3/creator/discover?searchField=$query&featuredBlogPosts=1&creatorStats=true'
          : 'v3/creator/discover?featuredBlogPosts=1&creatorStats=true';

      final subres = await fetchData(apiUrl, whitelabel);
      if (subres != null && subres.isNotEmpty) {
        List<dynamic> jsonList = jsonDecode(subres)['creators'];
        yield jsonList
            .map((json) => CreatorDiscoveryResponse.fromJson(json))
            .toList();
      }
    } catch (e) {
      yield [];
    }
  }

  Future<List<HistoryModelV3>> getHistory(String whitelabel,
      {int? offset}) async {
    try {
      int offsetInt = offset ?? 0;
      final response =
          await fetchData('v3/content/history?offset=$offsetInt', whitelabel);
      if (response != null && response.isNotEmpty) {
        List<dynamic> jsonList = jsonDecode(response);
        return jsonList.map((json) => HistoryModelV3.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Stream<CreatorModelV3> getCreator(String whitelabel,
      {String? urlname, int? id}) async* {
    try {
      final apiUrl = urlname != null
          ? 'v3/creator/named?creatorURL=$urlname'
          : 'v3/creator/info?id=$id';

      final creatorInfo = await fetchData(apiUrl, whitelabel);

      if (creatorInfo != null && creatorInfo.isNotEmpty) {
        List<dynamic> creatorList = jsonDecode(creatorInfo);
        if (creatorList.isNotEmpty) {
          Map<String, dynamic> creatorJson = creatorList.first;
          final freshCreator = CreatorModelV3.fromJson(creatorJson);
          yield freshCreator;
        }
      }
    } catch (e) {
      yield CreatorModelV3();
    }
  }

  Future<StatsModel> getStats(String whitelabel, String creatorId) async {
    try {
      final stats =
          await fetchData('v2/plan/info?creatorId=$creatorId', whitelabel);
      if (stats != null && stats.isNotEmpty) {
        dynamic statsJson = jsonDecode(stats);
        return StatsModel(
          totalIncome: statsJson['totalIncome'],
          totalSubcriberCount: statsJson['totalSubscriberCount'],
        );
      }
      return StatsModel(totalIncome: 0, totalSubcriberCount: 0);
    } catch (e) {
      return StatsModel(totalIncome: 0, totalSubcriberCount: 0);
    }
  }

  Future<Map<String, dynamic>> getStatsV3(
      String whitelabel, String creatorId) async {
    try {
      final stats =
          await fetchData('v3/creator/stats?id=$creatorId', whitelabel);
      if (stats != null && stats.isNotEmpty) {
        dynamic statsJson = jsonDecode(stats);
        return statsJson;
      }
      return {"error": true};
    } catch (e) {
      return {"error": true};
    }
  }

  Future<Map<String, dynamic>> getUserInfo(String whitelabel) async {
    try {
      final userinfo = await fetchData(
          'v3/user/self', whitelabel);
      if (userinfo != null && userinfo.isNotEmpty) {
        dynamic userinfoJson = jsonDecode(userinfo);
        return userinfoJson;
      }
      return {"error": true};
    } catch (e) {
      return {"error": true};
    }
  }

  Future<Map<String, dynamic>> getInvoices(String whitelabel) async {
    try {
      final invoices = await fetchData('v3/payment/invoice/list', whitelabel);
      if (invoices != null && invoices.isNotEmpty) {
        dynamic invoicesJson = jsonDecode(invoices);
        return invoicesJson;
      }
      return {"error": true};
    } catch (e) {
      return {"error": true};
    }
  }

  Stream<ContentPostV3Response> getBlogPost(
      String whitelabel, String blogPostId) async* {
    try {
      final apiUrl = 'v3/content/post?id=$blogPostId';
      final response = await fetchData(apiUrl, whitelabel);
      if (response != null && response.isNotEmpty) {
        try {
          final jsonData = jsonDecode(response);
          final parsed = ContentPostV3Response.fromJson(jsonData);
          yield parsed;
        } catch (e) {
          yield ContentPostV3Response();
        }
      } else {
        yield ContentPostV3Response();
      }
    } catch (e) {
      yield ContentPostV3Response();
    }
  }

  Future<String> likeBlogPost(String whitelabel, String blogPostId) async {
    final response = await postData('v3/content/like', whitelabel,
        {'contentType': 'blogPost', 'id': blogPostId});
    final decodedres = jsonDecode(response);
    if (decodedres.contains('like')) {
      return 'success';
    } else if (response.toString() == '[]') {
      return 'removed';
    } else {
      return 'fail';
    }
  }

  Future<String> dislikeBlogPost(String whitelabel, String blogPostId) async {
    final response = await postData('v3/content/dislike', whitelabel,
        {'contentType': 'blogPost', 'id': blogPostId});
    final decodedres = jsonDecode(response);
    if (decodedres.contains('dislike')) {
      return 'success';
    } else if (response.toString() == '[]') {
      return 'removed';
    } else {
      return 'fail';
    }
  }

  Future<String> likeComment(
      String whitelabel, String commentId, String blogPostId) async {
    final response = await postData('v3/comment/like', whitelabel,
        {'comment': commentId, 'blogPost': blogPostId});
    final decodedres = jsonDecode(response);
    if (decodedres.contains('like')) {
      return 'success';
    } else if (response.toString() == '[]') {
      return 'removed';
    } else {
      return 'fail';
    }
  }

  Future<String> dislikeComment(
      String whitelabel, String commentId, String blogPostId) async {
    final response = await postData('v3/comment/dislike', whitelabel,
        {'comment': commentId, 'blogPost': blogPostId});
    final decodedres = jsonDecode(response);
    if (decodedres.contains('dislike')) {
      return 'success';
    } else if (response.toString() == '[]') {
      return 'removed';
    } else {
      return 'fail';
    }
  }

  Future<List<BlogPostModelV3>> getRecommended(
      String whitelabel, String blogPostId) async {
    try {
      final response =
          await fetchData('v3/content/related?id=$blogPostId', whitelabel);
      if (response != null && response.isNotEmpty) {
        List<dynamic> decodedResponse = json.decode(response) as List<dynamic>;
        return decodedResponse
            .map((item) => BlogPostModelV3.fromJson(item))
            .toList();
      }
      return [];
    } catch (error) {
      return [];
    }
  }

  Future<List<CommentModel>> getComments(String whitelabel, String blogPostId,
      int limit, String sortBy, String sortOrder,
      {String? fetchAfter}) async {
    try {
      dynamic response;
      if (fetchAfter != null) {
        response = await fetchData(
            'v3/comment?blogPost=$blogPostId&limit=$limit&fetchAfter=$fetchAfter&sortBy=$sortBy&sortDirection=$sortOrder',
            whitelabel);
      } else {
        response = await fetchData(
            'v3/comment?blogPost=$blogPostId&limit=$limit&sortBy=$sortBy&sortDirection=$sortOrder',
            whitelabel);
      }

      if (response != null && response.isNotEmpty) {
        final List<dynamic> decodedData =
            json.decode(response) as List<dynamic>;
        return decodedData
            .map((item) => CommentModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (error) {
      return [];
    }
  }

  Future<List<CommentModel>> getReplies(String whitelabel, String comment,
      String blogPost, int limit, String rid) async {
    try {
      final response = await fetchData(
          'v3/comment/replies?comment=$comment&blogPost=$blogPost&limit=$limit&rid=$rid',
          whitelabel);

      if (response != null && response.isNotEmpty) {
        final List<dynamic> decodedData =
            json.decode(response) as List<dynamic>;
        return decodedData
            .map((item) => CommentModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (error) {
      return [];
    }
  }

  Future<CommentModel?> comment(
      String whitelabel, String blogPostId, String comment,
      {String? replyto}) async {
    try {
      final response = await postData('v3/comment', whitelabel, {
        'blogPost': blogPostId,
        if (replyto != null) 'replyTo': replyto,
        'text': comment
      });
      if (response.isNotEmpty) {
        final decodedData = json.decode(response) as Map<String, dynamic>;
        return CommentModel.fromJson(decodedData);
      }
      return null;
    } catch (error) {
      return null;
    }
  }

  Future<String> deleteComment(String whitelabel, String commentId) async {
    final response =
        await postData('v3/comment/delete?comment=$commentId', whitelabel, {});
    return response;
  }

  Future<String> editComment(
      String whitelabel, String commentId, String text) async {
    final response = await postData(
        'v3/comment/edit?comment=$commentId&text=$text', whitelabel, {});
    return response;
  }

  Future<String> getDelivery(
      String whitelabel, String scenario, String entityId) async {
    try {
      final res = await fetchData(
          'v3/delivery/info?scenario=$scenario&entityId=$entityId&outputKind=hls.mpegts',
          whitelabel);
      return res;
    } catch (e) {
      return '';
    }
  }

  Future<String> getDeliveryv2(
      String whitelabel, String type, String guid) async {
    try {
      final res =
          await fetchData('v2/cdn/delivery?type=$type&guid=$guid', whitelabel);
      return res;
    } catch (e) {
      return '';
    }
  }

  Future<String> getContent(String whitelabel, String type, String id) async {
    try {
      final res = await fetchData('v3/content/$type?id=$id', whitelabel);
      return res;
    } catch (e) {
      return '';
    }
  }

  Future<int> submitVote(String whitelabel, String id, int vote) async {
    final response =
        await postData('v3/poll/vote?pollId=$id&optionIndex=$vote', whitelabel);
    if (response == 'OK') {
      return 200;
    } else {
      return 500;
    }
  }

  //because of the dumb way i handle progress (i have 3 different things that can call progress) we debounce this to avoid spam and stale data.
  Timer? _progressDebounceTimer;
  final Map<String, Map<String, dynamic>> _pendingProgress = {};

  Future<void> progress(
      String whitelabel, String id, int progress, String contentType) async {
    if (id.isEmpty) return;
    _pendingProgress[id] = {
      'progress': progress,
      'contentType': contentType,
    };
    _progressDebounceTimer?.cancel();
    _progressDebounceTimer = Timer(const Duration(seconds: 5), () async {
      for (final entry in _pendingProgress.entries) {
        final String entryId = entry.key;
        final Map<String, dynamic> params = entry.value;

        await postData('v3/content/progress', whitelabel, {
          'id': entryId,
          'contentType': params['contentType'],
          'progress': params['progress'],
        });
      }
      _pendingProgress.clear();
    });
  }

  Future<void> iprogress(
      String whitelabel, String id, int progress, String contentType) async {
    if (id.isEmpty) return;
    await postData('v3/content/progress', whitelabel, {
      'id': id,
      'contentType': contentType,
      'progress': progress,
    });
  }

  Future<void> deleteHistory(String whitelabel) async {
    await postData('v3/content/progress/clear', whitelabel);
  }

  Future<String> logout(String whitelabel) async {
    final whiteLabel = whitelabels.getWhitelabel(whitelabel);
    final client = await getHttpClient(whiteLabel.friendlyName);
    final url = Uri.parse('${whiteLabel.apiUrl}/v3/auth/logout');
    final response = await client.post(
      url,
      headers: {'User-Agent': userAgent},
    );
    return response.body;
  }

  Future<Map<String, dynamic>> subscribe(
      String whitelabel, String creatorId) async {
    final whiteLabel = whitelabels.getWhitelabel(whitelabel);
    final client = await getHttpClient(whiteLabel.friendlyName);
    final url = Uri.parse('${whiteLabel.apiUrl}/v3/creator/subscribe?id=$creatorId');
    final response = await client.post(
      url,
      headers: {'User-Agent': userAgent},
    );
    return jsonDecode(response.body);
  }

  Future<String> unsubscribe(String whitelabel, String creatorId) async {
    final whiteLabel = whitelabels.getWhitelabel(whitelabel);
    final client = await getHttpClient(whiteLabel.friendlyName);
    final url = Uri.parse('${whiteLabel.apiUrl}/v3/creator/unsubscribe?id=$creatorId');
    final response = await client.post(
      url,
      headers: {'User-Agent': userAgent},
    );
    return response.body;
  }
}
