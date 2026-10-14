/// Simple example to generate audio with a preset voice using async/await.
///
/// Ported from edge-tts/examples/async_audio_gen_with_predefined_voice.py
library example.async_audio_gen_with_predefined_voice;

import 'dart:io';

import 'package:dart_edge_tts/dart_edge_tts.dart';

const String text = 'Hello World!';
const String voice = 'en-GB-SoniaNeural';
const String outputFile = 'test.mp3';

Future<void> main() async {
  final communicate = Communicate(text: text, voice: voice);
  await communicate.save(outputFile);
  stdout.writeln('Wrote $outputFile');
}
