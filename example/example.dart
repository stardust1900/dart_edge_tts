/// Basic example: generate an MP3 file with a predefined voice.
import 'dart:io';

import 'package:edge_tts/edge_tts.dart';

void main() async {
  const text = 'Hello World!';
  const voice = 'en-GB-SoniaNeural';
  const outputFile = 'example.mp3';

  final communicate = Communicate(text, voice);
  await communicate.save(outputFile);
  print('Wrote $outputFile');
  exit(0);
}
