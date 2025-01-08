import 'dart:convert';
import 'dart:io';

import 'package:dart_edge_tts/communicate.dart';
import 'package:dart_edge_tts/constants.dart';
import 'package:dart_edge_tts/data_classes.dart';
import 'package:dart_edge_tts/drm.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/status.dart' as status;

Future<void> main(List<String> args) async {
  final sslContext = SecurityContext.defaultContext;
  sslContext.setTrustedCertificates("${Directory.current.path}/lib/cacert.pem");
  final httpClient = HttpClient(context: sslContext);
  httpClient.findProxy = (uri) => "DIRECT"; // 禁用代理
  // Create WebSocket channel with SSL context
  final webSocketUrl = Uri.parse(
      "$wssUrl&Sec-MS-GEC=${DRM.generateSecMsGec()}&Sec-MS-GEC-Version=$secMsGecVersion&ConnectionId=${connectId()}");
  print(webSocketUrl);

  print(wssHeaders);
  // 创建 WebSocket 连接
  final webSocket = IOWebSocketChannel.connect(
    webSocketUrl,
    headers: wssHeaders,
    // protocols: ['json', 'binary'],
    customClient: httpClient,
  );
  print("Connecting to WebSocket server...");
  print(webSocket);
  // 监听服务器发来的消息
  webSocket.stream.listen(
    (message) {
      print("Received message: $message");
    },
    onDone: () {
      print("WebSocket connection closed.");
    },
    onError: (error) {
      print("WebSocket error: $error");
    },
  );

  // 发送一条消息到服务器
  print("Sending message to server...");

  String str1 = "X-Timestamp:${dateToString()}\r\n"
      "Content-Type:application/json; charset=utf-8\r\n"
      "Path:speech.config\r\n\r\n"
      '{"context":{"synthesis":{"audio":{"metadataoptions":{'
      '"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"true"},'
      '"outputFormat":"audio-24khz-48kbitrate-mono-mp3"'
      "}}}}\r\n";
  print("str1:$str1");
  webSocket.sink.add(
    str1,
  );

  final ttsConfig_ =
      TTSConfig.validate('en-GB-SoniaNeural', '+0%', '+0%', '+0Hz');
  String str2 = ssmlHeadersPlusData(
    connectId(),
    dateToString(),
    mkssml(ttsConfig_, "Hello World!"),
  );
  print("str2:$str2");

  webSocket.sink.add(
    str2,
  );

  // 保持连接一段时间，以便接收服务器的响应
  await Future.delayed(Duration(seconds: 5));

  // 关闭 WebSocket 连接
  print("Closing WebSocket connection...");
  webSocket.sink.close(status.normalClosure);
}
