import 'package:http/http.dart' as http;

void main() async {
  // 这个应该只是对dart:io里的client做了封装
  final response = await http.get(Uri.parse('https://example.com'));
  if (response.statusCode == 200) {
    print(response.body);
  } else {
    print('Request failed with status: ${response.statusCode}');
  }
}
