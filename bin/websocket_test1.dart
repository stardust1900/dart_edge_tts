import 'dart:io';
import 'dart:convert';

import 'package:dart_edge_tts/communicate.dart';
import 'package:dart_edge_tts/constants.dart';
import 'package:dart_edge_tts/drm.dart';

void main() async {
  final webSocketUrl = Uri.parse(
      "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4&Sec-MS-GEC=${DRM.generateSecMsGec()}&Sec-MS-GEC-Version=$secMsGecVersion&ConnectionId=${connectId()}");

  print(webSocketUrl);
  print(wssHeaders);

  final sslContext = SecurityContext.defaultContext;
  sslContext.setTrustedCertificates("${Directory.current.path}/lib/cacert.pem");
  final httpClient = HttpClient(context: sslContext);
  // 创建 WebSocket 连接
  final webSocket = await WebSocket.connect(
    webSocketUrl.toString(),
    // protocols: ['json', 'binary'],
    headers: wssHeaders,
    customClient: httpClient,
  );

  // 检查服务器选择的子协议
  print('Selected protocol: ${webSocket.protocol}');

  // 监听消息
  webSocket.listen(
    (message) => print('Received: $message'),
    onDone: () => print('Connection closed'),
    onError: (error) => print('Error: $error'),
  );

  // 发送消息
  webSocket.add(jsonEncode({'type': 'text', 'content': 'Hello, WebSocket!'}));

  // 保持连接一段时间
  await Future.delayed(Duration(seconds: 5));

  // 关闭连接
  webSocket.close();
}
