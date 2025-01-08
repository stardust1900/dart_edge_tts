import 'dart:convert';
import 'dart:io';
import 'dart:math';

void main() async {
  // 目标 WebSocket 服务器的地址和端口
  final host = 'echo.websocket.org';
  final port = 443; // HTTPS/WSS 端口

  // 创建 HttpClient 实例
  final client = HttpClient();

  try {
    // 发起 HTTPS 请求
    final request = await client.getUrl(Uri.https(host, '/'));
    print(request.headers);
    // 设置 HTTP 头部
    request.headers.add('Connection', 'Upgrade');
    request.headers.add('Upgrade', 'websocket');
    request.headers.add('Sec-WebSocket-Key', generateWebSocketKey());
    request.headers.add('Sec-WebSocket-Version', '13');
    request.headers.add('Origin', 'https://echo.websocket.org');

    // 发送请求并获取响应
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    // 打印完整的 HTTP 响应
    print('HTTP Status Code: ${response.statusCode}');
    print('Response Headers:');
    response.headers.forEach((name, values) {
      print('$name: $values');
    });
    print('Response Body:\n$responseBody');
  } catch (e) {
    print('Error: $e');
  } finally {
    // 关闭 HttpClient
    client.close();
  }
}

// 生成随机的 WebSocket Key
String generateWebSocketKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (index) => random.nextInt(256));
  return base64Encode(bytes);
}
