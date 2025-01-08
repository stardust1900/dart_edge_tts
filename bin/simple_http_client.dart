import 'dart:convert';
import 'dart:io';

Future<void> simpleHttpClient(String host, int port, String path) async {
  // Create a socket connection to the server.
  final Socket socket = await Socket.connect(host, port);

  // Send an HTTP GET request.
  final request = "GET $path HTTP/1.1\r\n"
      "Host: $host\r\n"
      "Connection: close\r\n"
      "\r\n";
  socket.write(request);

  // Listen for the response.
  await for (final data in socket) {
    print(utf8.decode(data));
  }

  // Close the socket when done.
  await socket.close();
}

void main() async {
  try {
    await simpleHttpClient('baidu.com', 80, '/');
  } catch (e) {
    print('Error: $e');
  }
}
