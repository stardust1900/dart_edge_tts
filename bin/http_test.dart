import 'dart:io';
import 'package:dart_edge_tts/constants.dart';
import 'package:dart_edge_tts/drm.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> arguments) async {
  final sslContext = SecurityContext.defaultContext;
  // sslContext.setTrustedCertificates(
  //     "D:/gitlab/dart-edge-tts/lib/cacert.pem"); // 替换为实际的证书路径

  sslContext.setTrustedCertificates("${Directory.current.path}/lib/cacert.pem");
  final client = http.Client();
  final url = Uri.parse(
      "$voiceListUrl&Sec-MS-GEC=${DRM.generateSecMsGec()}&Sec-MS-GEC-Version=$secMsGecVersion");

  print(url);
  var response = await client.get(
    url,
    headers: voiceHeaders,
    // 如果有代理，可以在这里设置
  );
  print(response.statusCode);
  print(response.body);
}
