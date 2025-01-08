import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

void main() async {
  // 目标 WebSocket 服务器的地址和端口
  final host = 'echo.websocket.org';
  final port = 443; // HTTPS/WSS 端口

  // 创建安全上下文
  final securityContext = SecurityContext.defaultContext;

  // 如果需要加载自定义 CA 证书，可以在这里加载
  // securityContext.setTrustedCertificates('path/to/ca_cert.pem');

  try {
    // 创建 SecureSocket 连接
    final socket =
        await SecureSocket.connect(host, port, context: securityContext);
    print('Connected to $host:$port');

    // 生成 WebSocket 握手请求
    final webSocketKey = base64Encode(Uint8List.fromList(List.generate(16,
        (_) => Random().nextInt(256)))); // 您可以使用 generateWebSocketKey() 生成随机值

    final handshakeRequest = "GET / HTTP/1.1\r\n"
        "Host: $host\r\n"
        "Connection: Upgrade\r\n"
        "Upgrade: websocket\r\n"
        "Sec-WebSocket-Key: $webSocketKey\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n";

    // 打印握手请求
    print('Handshake request:\n$handshakeRequest');
    print(handshakeRequest.contains('\r\n\r\n'));

    // 发送握手请求
    socket.write(handshakeRequest);

    // 监听服务器的响应
    String response = '';
    await for (var data in socket) {
      response += utf8.decode(data);
      if (response.contains('\r\n\r\n')) break; // 找到 HTTP 响应头结束标志
    }

    // 打印完整的 HTTP 响应
    print('Full HTTP response:\n$response');

    // 解析服务器的响应
    final headers = parseHttpHeaders(response);
    print(headers);
    final statusCodeString = headers['HTTP/1.1'];
    final statusCode = statusCodeString != null
        ? int.tryParse(statusCodeString.split(' ')[1])
        : null;

    if (statusCode == 101) {
      print('WebSocket handshake successful!');

      // 验证 Sec-WebSocket-Accept 头部
      final acceptHeader = headers['Sec-WebSocket-Accept'];
      if (acceptHeader != null &&
          validateWebSocketAccept(webSocketKey, acceptHeader)) {
        print('Sec-WebSocket-Accept header is valid.');

        // 开始 WebSocket 通信
        await communicateWithWebSocket(socket);
      } else {
        print('Invalid Sec-WebSocket-Accept header.');
      }
    } else {
      print(
          'WebSocket handshake failed with status code: ${statusCode ?? 'unknown'}');
    }

    // 关闭连接
    socket.close();
  } catch (e) {
    print('Error: $e');
  }
}

// 生成随机的 WebSocket Key
String generateWebSocketKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (index) => random.nextInt(256));
  return base64Encode(bytes);
}

// 验证 Sec-WebSocket-Accept 头部
bool validateWebSocketAccept(String webSocketKey, String acceptHeader) {
  final key = '$webSocketKey${_GUID}';
  final sha1Digest = sha1.convert(utf8.encode(key)).bytes;
  final expectedAccept = base64Encode(sha1Digest);
  return acceptHeader == expectedAccept;
}

const _GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

// 解析 HTTP 响应头部
Map<String, String> parseHttpHeaders(String response) {
  final headers = <String, String>{};
  final lines = response.split('\r\n');
  for (final line in lines) {
    if (line.isEmpty) break;
    final parts = line.split(': ');
    if (parts.length == 2) {
      headers[parts[0]] = parts[1];
    } else {
      headers['HTTP/1.1'] = line; // 处理第一行的 HTTP 版本和状态码
    }
  }
  return headers;
}

// 进行 WebSocket 通信
Future<void> communicateWithWebSocket(SecureSocket socket) async {
  // 发送一条 WebSocket 消息
  final message = 'Hello, WSS!';
  final frame = encodeWebSocketFrame(message);
  socket.add(frame);

  // 监听服务器的响应
  await for (var data in socket) {
    final frame = decodeWebSocketFrame(data);
    print('Received message: $frame');
  }
}

// 编码 WebSocket 帧
List<int> encodeWebSocketFrame(String message) {
  final payload = utf8.encode(message);
  final frame = <int>[];

  // 第一个字节：FIN=1, RSV=0, opcode=1 (text frame)
  frame.add(0x81);

  // 第二个字节：MASK=0, payload length
  if (payload.length <= 125) {
    frame.add(payload.length);
  } else if (payload.length <= 65535) {
    frame.add(126);
    frame.add((payload.length >> 8) & 0xFF);
    frame.add(payload.length & 0xFF);
  } else {
    frame.add(127);
    for (int i = 7; i >= 0; i--) {
      frame.add((payload.length >> (i * 8)) & 0xFF);
    }
  }

  // 添加 payload
  frame.addAll(payload);

  return frame;
}

// 解码 WebSocket 帧
String decodeWebSocketFrame(List<int> frame) {
  // 检查 FIN 位和 opcode
  final fin = (frame[0] & 0x80) != 0;
  final opcode = frame[0] & 0x0F;
  if (!fin || opcode != 1) {
    throw Exception('Invalid WebSocket frame');
  }

  // 检查 MASK 位
  final masked = (frame[1] & 0x80) != 0;
  if (masked) {
    throw Exception('Masked frames are not supported');
  }

  // 获取 payload length
  final payloadLength = frame[1] & 0x7F;
  int index = 2;
  if (payloadLength == 126) {
    index += 2;
  } else if (payloadLength == 127) {
    index += 8;
  }

  // 提取 payload
  final payload = frame.sublist(index);

  // 将 payload 解码为字符串
  return utf8.decode(payload);
}
