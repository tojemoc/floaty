import 'package:socket_io_client/socket_io_client.dart' as io;

void unifiedConnectionListener(
    Function(Map<String, dynamic>) handler, io.Socket socket) {
  socket.onConnect((_) {
    handler({'connected': true, 'color': 'success', 'message': 'Connected'});
  });

  socket.onConnectError((e) {
    handler(
        {'connected': false, 'color': 'error', 'message': 'Connection Error'});
  });

  socket.onDisconnect((e) {
    handler({'connected': false, 'color': 'error', 'message': 'Disconnected'});
  });

  socket.onReconnect((_) {
    handler({'connected': true, 'color': 'success', 'message': 'Reconnected'});
  });

  socket.onReconnectError((e) {
    handler(
        {'connected': false, 'color': 'error', 'message': 'Reconnect Error'});
  });

  socket.onReconnectAttempt((_) {
    handler(
        {'connected': false, 'color': 'warning', 'message': 'Reconnecting...'});
  });

  socket.onReconnectFailed((e) {
    handler(
        {'connected': false, 'color': 'error', 'message': 'Reconnect Failed'});
  });

  socket.onError((e) {
    handler({'connected': false, 'color': 'error', 'message': 'Error'});
  });
}
