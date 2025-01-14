import 'dart:convert';
import 'dart:io';

import 'package:dart_edge_tts/communicate.dart';
import 'package:dart_edge_tts/constants.dart';
import 'package:dart_edge_tts/data_classes.dart';
import 'package:dart_edge_tts/drm.dart';
import 'package:web_socket_channel/io.dart';

test() async {
// Create a new connection to the service.
  final sslContext = SecurityContext.defaultContext;
  sslContext.setTrustedCertificates("${Directory.current.path}/lib/cacert.pem");

  final webSocketUrl = Uri.parse(
    "$wssUrl&Sec-MS-GEC=${DRM.generateSecMsGec()}"
    "&Sec-MS-GEC-Version=$secMsGecVersion"
    "&ConnectionId=${connectId()}",
  );
  print("webSocketUrl:${webSocketUrl.toString()}");
  try {
    final webSocket = IOWebSocketChannel.connect(webSocketUrl,
        customClient: HttpClient(context: sslContext), headers: wssHeaders);

    webSocket.sink.add(
      "X-Timestamp:${dateToString()}\r\n"
      "Content-Type:application/json; charset=utf-8\r\n"
      "Path:speech.config\r\n\r\n"
      '{"context":{"synthesis":{"audio":{"metadataoptions":{'
      '"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"true"},'
      '"outputFormat":"audio-24khz-48kbitrate-mono-mp3"'
      "}}}}\r\n",
    );

    final ttsConfig_ = TTSConfig.validate(defaultVoice, '+0%', '+0%', '+0Hz');
    webSocket.sink.add(
      ssmlHeadersPlusData(
        connectId(),
        dateToString(),
        mkssml(ttsConfig_, "hello world"),
      ),
    );

    await for (final message in webSocket.stream) {
      print("message:$message");
    }
  } on WebSocketException catch (e) {
    print('WebSocket connection error: $e');
  }
}

Future<void> main(List<String> args) async {
  try {
    String txt = "锄禾日当午，汗滴禾下土。谁知盘中餐，粒粒皆辛苦。";
    var communicate = Communicate(text: txt);
    // communicate.stream();
    await communicate.save("test.mp3");
  } catch (e, stackTrace) {
    print(e);
    print(stackTrace);
  }

  // test();
}
