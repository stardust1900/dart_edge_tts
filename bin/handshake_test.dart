import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:dart_edge_tts/communicate.dart';
import 'package:dart_edge_tts/constants.dart';
import 'package:dart_edge_tts/drm.dart';

void main(List<String> args) {
  var uri = Uri.parse(
      "https://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4&Sec-MS-GEC=${DRM.generateSecMsGec()}&Sec-MS-GEC-Version=$secMsGecVersion&ConnectionId=${connectId()}");
  // print(uri.userInfo);
  // uri = Uri(
  //     scheme: uri.isScheme("wss") ? "https" : "http",
  //     userInfo: uri.userInfo,
  //     host: uri.host,
  //     port: uri.port,
  //     path: uri.path,
  //     query: uri.query,
  //     fragment: uri.fragment.isNotEmpty ? uri.fragment : null);
  print(uri);
  final sslContext = SecurityContext.defaultContext;
  sslContext.setTrustedCertificates("${Directory.current.path}/lib/cacert.pem");
  final httpClient = HttpClient(context: sslContext);

  httpClient.openUrl("GET", uri).then((request) {
    print("headers before:${request.headers}");
    request.headers.clear();
    // wssHeaders.forEach((field, value) => request.headers.set(field, value));
    Random random = Random();
    // Generate 16 random bytes.
    Uint8List nonceData = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      nonceData[i] = random.nextInt(256);
    }
    String nonce = base64Encode(nonceData);
    // request.headers
    //   ..set(HttpHeaders.upgradeHeader, "websocket")
    //   ..set(HttpHeaders.connectionHeader, "Upgrade")
    //   ..set("Sec-WebSocket-Key", nonce)
    //   ..set("Sec-WebSocket-Version", "13");

    request.headers.add("Pragma", "no-cache");
    request.headers.add("Cache-Control", "no-cache");
    request.headers
        .add("Origin", "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold");
    request.headers.add("User-Agent",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0");
    request.headers.add("Accept-Encoding", "gzip, deflate, br");
    request.headers.add("Accept-Language", "en-US,en;q=0.9");
    request.headers.add("Upgrade", "websocket");
    request.headers.add("Connection", "Upgrade");
    request.headers.add("Sec-WebSocket-Version", "13");
    request.headers.add("Sec-WebSocket-Key", nonce);

    print("headers after:${request.headers}");
    print("request:$request");
    return request.close();
  }).then((response) {
    print("response:$response");
    print(response.headers);
    print(response.statusCode);
  });
}
