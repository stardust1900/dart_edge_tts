import 'dart:io';

import 'package:dart_edge_tts/dart_edge_tts.dart' as dart_edge_tts;
import 'package:dart_edge_tts/voices.dart';

void main(List<String> arguments) {
  // print('Hello world: ${dart_edge_tts.calculate()}!');
  var vm = VoicesManager.create();
  print(vm);
  // String currentPath = Directory.current.path;
  // print(currentPath);
  // var scriptPath = Platform.script.toFilePath;
  // print(scriptPath);
}
