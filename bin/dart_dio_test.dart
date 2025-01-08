import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart_edge_tts/communicate.dart';
import 'package:dart_edge_tts/constants.dart';
import 'package:dart_edge_tts/drm.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

void main() async {
  final sslContext = SecurityContext.defaultContext;
  try {
    // 将 CA 证书添加到 SecurityContext
    sslContext
        .setTrustedCertificates("${Directory.current.path}/lib/cacert.pem");
  } catch (e) {
    print('Failed to load CA certificate: $e');
    return;
  }

  var uri = Uri.parse(
      "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4&Sec-MS-GEC=${DRM.generateSecMsGec()}&Sec-MS-GEC-Version=$secMsGecVersion&ConnectionId=${connectId()}");

  final dio = Dio();

// 设置 HttpClientAdapter 为 IOHttpClientAdapter 并应用自定义的 SecurityContext
  (dio.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate = (client) {
    // 创建一个新的 HttpClient 实例并传递 SecurityContext
    final customClient = HttpClient(context: sslContext);
    return customClient;
  };

  dio.options.headers = {
    "Pragma": "no-cache",
    "Cache-Control": "no-cache",
    "Origin": "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold",
    "User-Agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0",
    "Accept-Encoding": "gzip, deflate, br",
    "Accept-Language": "en-US,en;q=0.9",
    "Upgrade": "websocket",
    "Connection": "Upgrade",
    "Sec-WebSocket-Version": "13",
    "Sec-WebSocket-Key": base64Encode(
        Uint8List.fromList(List.generate(16, (_) => Random().nextInt(256))))
  };
  print(dio.options.headers);
  try {
    final response = await dio.get(uri.toString());
    print(response.statusCode);
    print(response.headers);
  } catch (e) {
    print('Request failed: $e');
  }
}
