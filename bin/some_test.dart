import 'dart:convert';

import 'package:dart_edge_tts/communicate.dart';

void main(List<String> args) {
  String text = "这是一个需要分割的示例文本，它将被分成多个较小的部分。";
  int byteLength = 20;

  for (final segment in splitTextByByteLength(text, byteLength)) {
    print(segment);
  }
}
