import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart_edge_tts/communicate.dart';
import 'package:dart_edge_tts/constants.dart';
import 'package:dart_edge_tts/drm.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

Future<http.Client> createHttpClientWithSSL() async {
  // 读取证书文件
  final sslContext = SecurityContext.defaultContext;
  sslContext.setTrustedCertificates("${Directory.current.path}/lib/cacert.pem");
  final httpClient = HttpClient(context: sslContext);

  // 创建 IOClient 并传递 HttpClient
  return IOClient(httpClient);
}

void testHttpConnection() async {
  final url = Uri.https(
    'speech.platform.bing.com',
    '/consumer/speech/synthesize/readaloud/edge/v1',
    {
      'TrustedClientToken': '6A5AA1D4EAFF4E9FB37E23D68491D6F4',
      'Sec-MS-GEC': DRM.generateSecMsGec(),
      'Sec-MS-GEC-Version': secMsGecVersion,
      'ConnectionId': connectId(),
    },
  );

  try {
    // 加载 SSL 证书并创建 HttpClient
    // final client = await createHttpClientWithSSL();
    // Create an HttpClient with SSL context
    // final httpClient = HttpClient()
    //   ..badCertificateCallback =
    //       (X509Certificate cert, String host, int port) => true;

    final sslContext = SecurityContext.defaultContext;
    sslContext
        .setTrustedCertificates("${Directory.current.path}/lib/cacert.pem");
    final httpClient = HttpClient(context: sslContext);
    final req = await httpClient.openUrl("GET", url);
    print(req.headers);

    print(url);
    final client = IOClient(httpClient);
    // 创建 BaseRequest 实例
    final request = http.Request('GET', url);
    print(request.headers);
    print("================================");
    // // 手动设置请求头，保持原始大小写和顺序

    request.headers["Pragma"] = "no-cache";
    request.headers["Cache-Control"] = "no-cache";
    request.headers["Origin"] =
        "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold";
    request.headers["User-Agent"] =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0";
    request.headers["Accept-Encoding"] = "gzip, deflate, br";
    request.headers["Accept-Language"] = "en-US,en;q=0.9";
    request.headers["Upgrade"] = "websocket";
    request.headers["Connection"] = "Upgrade";
    request.headers["Sec-WebSocket-Version"] = "13";
    request.headers["Sec-WebSocket-Key"] = base64Encode(
        Uint8List.fromList(List.generate(16, (_) => Random().nextInt(256))));
    print(request.headers);
    final response = await client.send(request);
    // final handShakeUri = Uri(
    //     scheme: "https",
    //     host: url.host,
    //     path: url.path + (url.query.isNotEmpty ? "?${url.query}" : ""));
    // print("handShakeUri:$handShakeUri");
    // HttpClientRequest request = await httpClient.getUrl(url);
    // print(request.headers);
    // // request.headers.clear();
    // print("====================================");
    // request.headers.set("Pragma", "no-cache");
    // request.headers.set("Cache-Control", "no-cache");
    // request.headers
    //     .set("Origin", "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold");
    // request.headers.set("User-Agent",
    //     "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0");
    // request.headers.set("Accept-Encoding", "gzip, deflate, br");
    // request.headers.set("Accept-Language", "en-US,en;q=0.9");
    // request.headers.set("Upgrade", "websocket");
    // request.headers.set("Connection", "Upgrade");
    // request.headers.set("Sec-WebSocket-Version", "13");
    // request.headers.set(
    //     "Sec-WebSocket-Key",
    //     base64Encode(Uint8List.fromList(
    //         List.generate(16, (_) => Random().nextInt(256)))));

    // print(request.headers);
    // final response = await request.close();

    print("HTTP Response: ${response.statusCode}");
    print("Response headers: ${response.headers}");
  } catch (e) {
    print("HTTP request failed: $e");
  }
}

void main() async {
  testHttpConnection();
}
