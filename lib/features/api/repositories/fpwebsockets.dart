import 'dart:async';
import 'package:floaty/features/authentication/services/oauth2_service.dart';
import 'package:floaty/whitelabels.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io_client;
import 'package:sails_io/sails_io.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

final FPWebsockets fpWebsockets = GetIt.I<FPWebsockets>();

class FPWebsockets {
  static final Logger _log = Logger('FPWebsockets');

  SailsIOClient? _io;
  SailsIOClient? _fpio;
  String? liveid;
  final String userAgent;
  final WhiteLabel whitelabel;
  Function(dynamic)? _radioChatterHandler;
  Function(dynamic)? _pollOpenHandler;
  Function(dynamic)? _pollCloseHandler;
  Function(dynamic)? _pollUpdateTallyHandler;

  FPWebsockets({
    required this.whitelabel,
    required this.userAgent,
  }) {
    _log.info('FPWebsockets created for ${whitelabel.friendlyName}');
  }

  /// Get fresh auth headers
  Future<Map<String, String>> _getFreshHeaders() async {
    final authHeaders =
        await OAuth2Service.instance.getAuthHeaders(whitelabel.friendlyName);
    return {
      'User-Agent': userAgent,
      'Origin': 'https://www.floatplane.com',
      ...authHeaders,
    };
  }

  /// Create or recreate the chat socket with fresh headers
  Future<SailsIOClient> _createChatSocket() async {
    _log.info('Creating chat socket with fresh headers');
    final headers = await _getFreshHeaders();
    _log.fine('Chat socket headers: $headers');

    return SailsIOClient(socket_io_client.io(
      'https://pp-chat.floatplane.com?__sails_io_sdk_version=1.2.1&__sails_io_sdk_platform=node&__sails_io_sdk_language=javascript&EIO=3',
      socket_io_client.OptionBuilder()
          .setTransports(['websocket'])
          .setExtraHeaders(headers)
          .disableAutoConnect()
          .disableReconnection() // We'll handle reconnection manually with fresh headers
          .enableForceNew()
          .enableForceNewConnection()
          .build(),
    ));
  }

  /// Create or recreate the main socket with fresh headers
  Future<SailsIOClient> _createMainSocket() async {
    _log.info('Creating main socket with fresh headers');
    final headers = await _getFreshHeaders();
    _log.fine('Main socket headers: $headers');

    return SailsIOClient(socket_io_client.io(
      'https://www.floatplane.com?__sails_io_sdk_version=1.2.1&__sails_io_sdk_platform=node&__sails_io_sdk_language=javascript&EIO=3',
      socket_io_client.OptionBuilder()
          .setTransports(['websocket'])
          .setExtraHeaders(headers)
          .disableAutoConnect()
          .disableReconnection() // We'll handle reconnection manually with fresh headers
          .enableForceNew()
          .enableForceNewConnection()
          .build(),
    ));
  }

  // ============================================================
  // CHAT FUNCTIONALITY
  // ============================================================

  void chatConnect(
      String liveId,
      Function(Map<String, dynamic>) messagesHandler,
      Function(Map<String, dynamic>) connectionHandler) async {
    _log.info('Connecting to chat for liveId: $liveId');
    liveid = liveId;

    // Create fresh socket with current auth headers
    _io = await _createChatSocket();

    _io!.socket.onConnect((_) {
      _log.info('Chat socket connected');
      connectionHandler(
          {'connected': true, 'color': 'success', 'message': 'Connected'});
    });

    _io!.socket.onDisconnect((_) {
      _log.warning('Chat socket disconnected');
      connectionHandler(
          {'connected': false, 'color': 'warning', 'message': 'Disconnected'});

      // Auto-reconnect with fresh headers after a delay
      _scheduleReconnect(
          () => _reconnectChat(liveId, messagesHandler, connectionHandler));
    });

    _io!.socket.onConnectError((error) {
      _log.severe('Chat socket connection error: $error');
      connectionHandler({
        'connected': false,
        'color': 'error',
        'message': 'Connection Error'
      });
    });

    _io!.socket.onError((error) {
      _log.severe('Chat socket error: $error');
    });

    // Set up radioChatter handler
    if (_radioChatterHandler != null) {
      _io!.socket.off('radioChatter', _radioChatterHandler!);
    }
    _radioChatterHandler = (data) {
      _log.fine('radioChatter event: $data');
      messagesHandler({'socket': 'chat', 'type': 'radioChatter', 'data': data});
    };
    _io!.socket.on('radioChatter', _radioChatterHandler!);

    // Connect and join room
    _io!.socket.connect();

    // Wait a moment for connection before joining room
    _io!.socket.onConnect((_) {
      joinLiveChatRoom(liveId, messagesHandler);
    });
  }

  /// Reconnect chat with fresh headers
  Future<void> _reconnectChat(
      String liveId,
      Function(Map<String, dynamic>) messagesHandler,
      Function(Map<String, dynamic>) connectionHandler) async {
    _log.info('Reconnecting chat with fresh headers...');

    // Dispose old socket
    _io?.socket.dispose();

    // Create new socket with fresh headers and reconnect
    chatConnect(liveId, messagesHandler, connectionHandler);
  }

  void chatDisconnect(Function(Map<String, dynamic>) connectionHandler) {
    _log.info('Disconnecting from chat');
    _io?.socket.disconnect();
    _io?.socket.dispose();
    _io = null;
    liveid = null;
    connectionHandler(
        {'connected': false, 'color': 'success', 'message': 'Disconnected'});
  }

  void joinLiveChatRoom(
      String id, Function(Map<String, dynamic>) messagesHandler) {
    _log.info('Joining live chat room: /live/$id');
    liveid = id;

    _io?.get(
      url: '/RadioMessage/joinLivestreamRadioFrequency',
      data: {'channel': '/live/$id', 'message': null},
      cb: (data, jwr) {
        _log.info('joinLiveChatRoom response: ${jwr.statusCode}');
        _log.fine('joinLiveChatRoom data: $data');
        messagesHandler(
            {'socket': 'chat', 'type': 'joinResponse', 'data': data});
      },
    );
  }

  void sendChatMessage(String id, String message,
      Function(Map<String, dynamic>) messagesHandler) {
    _log.fine('Sending chat message to /live/$id');

    _io?.post(
      url: '/RadioMessage/sendLivestreamRadioChatter',
      data: {'channel': '/live/$id', 'message': message},
      cb: (data, jwr) {
        _log.fine('sendChatMessage response: ${jwr.statusCode}');
        messagesHandler(
            {'socket': 'chat', 'type': 'messageResponse', 'data': data});
      },
    );
  }

  void getChatUserList(
      String id, Function(Map<String, dynamic>) messagesHandler) {
    _log.fine('Getting chat user list for /live/$id');

    _io?.get(
      url: '/RadioMessage/getChatUserList',
      data: {'channel': '/live/$id'},
      cb: (data, jwr) {
        _log.fine('getChatUserList response: ${jwr.statusCode}');
        messagesHandler(
            {'socket': 'chat', 'type': 'getChatUserList', 'data': data});
      },
    );
  }

  // ============================================================
  // POLL FUNCTIONALITY
  // ============================================================

  void pollConnect(
      String creatorId, Function(Map<String, dynamic>) messagesHandler) async {
    _log.info('Connecting to polls for creatorId: $creatorId');

    // Create fresh socket with current auth headers
    _fpio = await _createMainSocket();

    _fpio!.socket.onConnect((_) {
      _log.info('Main socket connected');
    });

    _fpio!.socket.onDisconnect((_) {
      _log.warning('Main socket disconnected');

      // Auto-reconnect with fresh headers after a delay
      _scheduleReconnect(() => _reconnectPoll(creatorId, messagesHandler));
    });

    _fpio!.socket.onConnectError((error) {
      _log.severe('Main socket connection error: $error');
    });

    _fpio!.socket.onError((error) {
      _log.severe('Main socket error: $error');
    });

    _fpio!.socket.on('post', (data) {
      _log.fine('Main socket post event: $data');
    });

    // Set up poll event handlers
    _setupPollHandlers(messagesHandler);

    // Connect and join poll room
    _fpio!.socket.connect();

    _fpio!.socket.onConnect((_) {
      joinPollRoom(creatorId, messagesHandler);
    });
  }

  /// Reconnect poll socket with fresh headers
  Future<void> _reconnectPoll(
      String creatorId, Function(Map<String, dynamic>) messagesHandler) async {
    _log.info('Reconnecting poll socket with fresh headers...');

    // Dispose old socket
    _fpio?.socket.dispose();

    // Create new socket with fresh headers and reconnect
    pollConnect(creatorId, messagesHandler);
  }

  void _setupPollHandlers(Function(Map<String, dynamic>) messagesHandler) {
    if (_fpio == null) return;

    // Poll Open Handler
    if (_pollOpenHandler != null) {
      _fpio!.socket.off('pollOpen', _pollOpenHandler!);
    }
    _pollOpenHandler = (data) {
      _log.info('Poll opened: $data');
      messagesHandler({'socket': 'poll', 'type': 'open', 'data': data});
    };
    _fpio!.socket.on('pollOpen', _pollOpenHandler!);

    // Poll Close Handler
    if (_pollCloseHandler != null) {
      _fpio!.socket.off('pollClose', _pollCloseHandler!);
    }
    _pollCloseHandler = (data) {
      _log.info('Poll closed: $data');
      messagesHandler({'socket': 'poll', 'type': 'close', 'data': data});
    };
    _fpio!.socket.on('pollClose', _pollCloseHandler!);

    // Poll Update Tally Handler
    if (_pollUpdateTallyHandler != null) {
      _fpio!.socket.off('pollUpdateTally', _pollUpdateTallyHandler!);
    }
    _pollUpdateTallyHandler = (data) {
      _log.fine('Poll tally updated: $data');
      messagesHandler({'socket': 'poll', 'type': 'updateTally', 'data': data});
    };
    _fpio!.socket.on('pollUpdateTally', _pollUpdateTallyHandler!);
  }

  void pollDisconnect(
      String creatorId, Function(Map<String, dynamic>) messagesHandler) {
    _log.info('Disconnecting from polls');
    leavePollRoom(creatorId, messagesHandler);
  }

  Future<void> joinPollRoom(
      String id, Function(Map<String, dynamic>) messagesHandler) async {
    _log.info('Joining poll room for creator: $id');

    // Get fresh headers for this request
    final headers =
        await OAuth2Service.instance.getAuthHeaders(whitelabel.friendlyName);

    _fpio?.post(
      url: '/api/v3/poll/live/joinroom',
      data: {'creatorId': id},
      headers: headers,
      cb: (data, jwr) {
        _log.info('joinPollRoom response: ${jwr.statusCode}');
        _log.fine('joinPollRoom data: $data');
        messagesHandler(
            {'socket': 'poll', 'type': 'joinResponse', 'data': data});
      },
    );
  }

  Future<void> leavePollRoom(
      String id, Function(Map<String, dynamic>) messagesHandler) async {
    _log.info('Leaving poll room for creator: $id');

    // Get fresh headers for this request
    final headers =
        await OAuth2Service.instance.getAuthHeaders(whitelabel.friendlyName);

    _fpio?.post(
      url: '/api/v3/poll/live/leaveroom',
      data: {'creatorId': id},
      headers: headers,
      cb: (data, jwr) {
        _log.info('leavePollRoom response: ${jwr.statusCode}');
        messagesHandler(
            {'socket': 'poll', 'type': 'leaveResponse', 'data': data});
      },
    );

    _fpio?.socket.disconnect();
    _fpio?.socket.dispose();
    _fpio = null;
  }

  // ============================================================
  // HELPERS
  // ============================================================

  Timer? _reconnectTimer;

  /// Schedule a reconnect with exponential backoff
  void _scheduleReconnect(Future<void> Function() reconnectFn) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(minutes: 30), () async {
      await reconnectFn();
    });
  }

  /// Dispose all resources
  void dispose() {
    _reconnectTimer?.cancel();
    _io?.socket.dispose();
    _fpio?.socket.dispose();
    _io = null;
    _fpio = null;
  }
}
