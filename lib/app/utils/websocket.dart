import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';

class Websocket {
  final String url;
  final String userAgent;
  final String? proxy;
  final void Function(String message)? onMessage;
  final void Function()? onDone;
  final void Function(dynamic err)? onError;
  WebSocketChannel? _channel;

  Websocket({
    required this.url,
    required this.userAgent,
    this.proxy,
    this.onMessage,
    this.onDone,
    this.onError,
  });

  Future<void> connect() async {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _channel!.stream.listen(
        (data) {
          onMessage?.call(data.toString());
        },
        onDone: () {
          onDone?.call();
        },
        onError: (err) {
          onError?.call(err);
        },
      );
    } catch (err) {
      onError?.call(err);
    }
  }

  bool connected() => _channel != null && _channel!.closeCode == null;

  Future<void> disconnect() async {
    _channel?.sink.close();
  }

  void close() {
    _channel?.sink.close();
  }
}
