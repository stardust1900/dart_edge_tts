import 'dart:typed_data';

void main() {
  Uint8List message = Uint8List.fromList([0, 128, 88, 45]); // 实际数据

  // 方法1: 使用 reduce，假设大端序
  int headerLength1 =
      message.sublist(0, 2).reduce((value, element) => (value << 8) | element);

  print(message.buffer);
  // 方法2: 使用 ByteData.view，明确指定大端序
  final headerLength = ByteData.view(message.buffer).getUint16(0, Endian.big);

  print("Header Length1 (reduce): $headerLength1");
  print("Header Length (ByteData): $headerLength");
}
