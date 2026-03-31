import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// P2P direct signaling fallback when the signaling server is down.
/// Each app hosts a lightweight HTTP endpoint for SDP exchange.
class DirectSignaling {
  HttpServer? _server;
  final int port;
  final void Function(Map<String, dynamic> message)? onMessage;

  DirectSignaling({this.port = 8090, this.onMessage});

  /// Start the local HTTP server for receiving direct signals
  Future<void> startServer() async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      debugPrint('DirectSignaling: listening on port $port');

      _server!.listen((request) async {
        if (request.method == 'POST' && request.uri.path == '/api/direct-signal') {
          try {
            final body = await utf8.decoder.bind(request).join();
            final message = jsonDecode(body) as Map<String, dynamic>;
            onMessage?.call(message);
            request.response
              ..statusCode = 200
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'ok'}));
            await request.response.close();
          } catch (e) {
            request.response
              ..statusCode = 400
              ..write(jsonEncode({'error': e.toString()}));
            await request.response.close();
          }
        } else {
          request.response
            ..statusCode = 404
            ..write('Not found');
          await request.response.close();
        }
      });
    } catch (e) {
      debugPrint('DirectSignaling: failed to start server: $e');
    }
  }

  /// Send a signal directly to the peer via HTTP POST
  static Future<bool> sendToPeer(
      String peerIp, int port, Map<String, dynamic> message) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);

      final uri = Uri.parse('http://$peerIp:$port/api/direct-signal');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(message));

      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      client.close();

      if (response.statusCode == 200) {
        debugPrint('DirectSignaling: sent to $peerIp successfully');
        return true;
      } else {
        debugPrint('DirectSignaling: peer returned ${response.statusCode}: $body');
        return false;
      }
    } catch (e) {
      debugPrint('DirectSignaling: failed to send to $peerIp: $e');
      return false;
    }
  }

  /// Stop the local HTTP server
  Future<void> stopServer() async {
    await _server?.close();
    _server = null;
    debugPrint('DirectSignaling: server stopped');
  }
}
