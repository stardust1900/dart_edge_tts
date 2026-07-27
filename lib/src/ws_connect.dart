/// Manual WebSocket handshake for Microsoft Edge's TTS service.
///
/// `dart:io`'s [WebSocket.connect] has been observed to mangle or drop the
/// `Origin` header (and to surface unhelpful 403s without a response body).
/// This module performs the RFC 6455 upgrade handshake by hand so every
/// header — especially `Origin` — is forwarded verbatim, exactly as the
/// Python `edge_tts` reference does. The upgraded socket is then wrapped with
/// `WebSocket.fromUpgradedSocket` and exposed through an [IOWebSocketChannel].
library;

import 'dart:async';
import 'dart:convert' show base64Encode, utf8;
import 'dart:io';
import 'dart:math';

import 'package:web_socket_channel/io.dart';

/// Performs a manual WebSocket upgrade against [url] (ws:// or wss://) and
/// returns a ready-to-use [IOWebSocketChannel].
///
/// [headers] are added to the request verbatim (no filtering). [proxy] is an
/// optional `http(s)://host:port` proxy. [connectTimeout] bounds the TCP
/// connect. On a non-101 response the server body is read and surfaced in the
/// thrown error (crucial for diagnosing 403s).
Future<IOWebSocketChannel> connectEdgeWebSocket(
  String url, {
  required Map<String, dynamic> headers,
  String? proxy,
  Duration connectTimeout = const Duration(seconds: 10),
}) async {
  final uri = Uri.parse(url);
  if (!uri.isScheme('wss') && !uri.isScheme('ws')) {
    throw ArgumentError('connectEdgeWebSocket expects a ws/wss URL, got: $url');
  }

  // wss -> https for the underlying HTTP upgrade request.
  final httpUri = uri.replace(scheme: uri.isScheme('wss') ? 'https' : 'http');

  final client = HttpClient();
  client.connectionTimeout = connectTimeout;
  if (proxy != null) {
    var hostPort = proxy;
    final m = RegExp(r'^https?://([^/]+)').firstMatch(proxy);
    if (m != null) hostPort = m.group(1)!;
    client.findProxy = (Uri _) => 'PROXY $hostPort;';
  }

  // dart:io injects its own default `User-Agent: Dart/x.y (dart:io)` header,
  // which Microsoft's WAF rejects (403). We must override the client-level
  // User-Agent with the browser one from [headers] and avoid adding it twice.
  String? browserUserAgent;
  headers.forEach((field, value) {
    if (field.toLowerCase() == 'user-agent') {
      browserUserAgent = value is List ? value.last as String : value as String;
    }
  });
  if (browserUserAgent != null) client.userAgent = browserUserAgent;

  // RFC 6455: 16 random bytes, base64-encoded, as the Sec-WebSocket-Key.
  final rng = Random.secure();
  final nonce = base64Encode(List<int>.generate(16, (_) => rng.nextInt(256)));

  HttpClientResponse response;
  try {
    final request = await client.openUrl('GET', httpUri);
    // User headers first so the mandatory upgrade headers can assert after.
    // Skip `user-agent` (already applied via client.userAgent) to send it once.
    headers.forEach((field, value) {
      if (field.toLowerCase() == 'user-agent') return;
      if (value is List) {
        for (final v in value) request.headers.add(field, v);
      } else {
        request.headers.add(field, value);
      }
    });
    request.headers
      ..set(HttpHeaders.connectionHeader, 'Upgrade')
      ..set(HttpHeaders.upgradeHeader, 'websocket')
      ..set('Sec-WebSocket-Key', nonce)
      ..set('Sec-WebSocket-Version', '13');

    response = await request.close();
  } catch (e) {
    client.close(force: true);
    throw WebSocketException('WebSocket handshake failed to open: $e');
  }

  if (response.statusCode != HttpStatus.switchingProtocols) {
    final body = await response.transform(utf8.decoder).join();
    client.close(force: true);
    throw WebSocketException(
      'WebSocket upgrade rejected with HTTP ${response.statusCode}: $body',
    );
  }

  // The socket now speaks the WebSocket protocol. Detach it from the HTTP
  // stack and hand it to dart:io's WebSocket implementation as the client
  // (serverSide: false => we mask outgoing frames, per the spec).
  final socket = await response.detachSocket();
  // The detached socket is no longer owned by the client; closing the client
  // is safe and frees the connection pool.
  client.close(force: true);

  final webSocket = WebSocket.fromUpgradedSocket(
    socket,
    serverSide: false,
    compression: CompressionOptions.compressionOff,
  );
  return IOWebSocketChannel(webSocket);
}
