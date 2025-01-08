import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart_edge_tts/communicate.dart';
import 'package:dart_edge_tts/constants.dart';
import 'package:dart_edge_tts/drm.dart';

void main() async {
  final host = 'speech.platform.bing.com';
  // final host = 'localhost';
  final port = 443;
  // final port = 8080;
  final securityContext = SecurityContext.defaultContext;
  securityContext
      .setTrustedCertificates("${Directory.current.path}/lib/cacert.pem");
  print(Directory.current.path);
  final socket =
      await SecureSocket.connect(host, port, context: securityContext);
  // final socket = await Socket.connect(host, port);
  print('Connected to $host:$port');

  final webSocketKey = base64Encode(
      Uint8List.fromList(List.generate(16, (_) => Random().nextInt(256))));
  final path =
      "/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4&Sec-MS-GEC=${DRM.generateSecMsGec()}&Sec-MS-GEC-Version=$secMsGecVersion&ConnectionId=${connectId()}";
  // final path =
  //     "/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4&Sec-MS-GEC=B33D47AA68329C69E16989C0AD0B650423AAEA1A9F9D8CE28A6722388F855570&Sec-MS-GEC-Version=$secMsGecVersion&ConnectionId=f068ec7ee1d64e9c9404b4930a87158c";

  // final path = "/ngTest/hello";
  print('path:$path');

  final handshakeRequest = "GET $path HTTP/1.1\r\n"
      "Host: $host\r\n"
      "Upgrade: websocket\r\n"
      "Connection: Upgrade\r\n"
      "Sec-WebSocket-Key: $webSocketKey\r\n"
      "Sec-WebSocket-Version: 13\r\n"
      "Pragma: no-cache\r\n"
      "Cache-Control: no-cache\r\n"
      "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0\r\n"
      "Accept-Language: en-US,en;q=0.9\r\n"
      "Origin: chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold\r\n"
      "Accept: */*\r\n"
      "Accept-Encoding: gzip, deflate, br\r\n"
      "\r\n";

  print('Handshake request:\n$handshakeRequest');
  socket.write(handshakeRequest);

  // socket.writeln("GET $path HTTP/1.1");
  // socket.writeln("Host: $host");
  // socket.writeln("Pragma: no-cache");
  // socket.writeln("Cache-Control: no-cache");
  // socket.writeln("Origin: chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold");
  // socket.writeln(
  //     "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0");
  // socket.writeln("Accept-Encoding: gzip, deflate, br");
  // socket.writeln("Accept-Language: en-US,en;q=0.9");
  // socket.writeln("Upgrade: websocket");
  // socket.writeln("Connection: Upgrade");
  // socket.writeln("Sec-WebSocket-Version: 13");
  // socket.writeln("Sec-WebSocket-Key: $webSocketKey");
  // socket.writeln("Accept: */*");
  // socket.writeln();

  // 监听服务器的响应
  String response = '';
  await for (var data in socket) {
    response += utf8.decode(data);
    if (response.contains('\r\n\r\n')) break; // 找到 HTTP 响应头结束标志
  }
  // 打印完整的 HTTP 响应
  print('Full HTTP response:\n$response');

  // 关闭连接
  socket.close();
}
