/// Sync variant of the example for generating audio with a predefined voice.
///
/// Ported from edge-tts/examples/sync_audio_gen_with_predefined_voice.py
library example.sync_audio_gen_with_predefined_voice;

import 'dart:io';

import 'package:dart_edge_tts/dart_edge_tts.dart';

const String text = 'Hello World!';
const String voice = 'en-GB-SoniaNeural';
const String outputFile = 'test.mp3';

void main() {
  final communicate = Communicate(text: text, voice: voice);
  communicate.saveSync(outputFile);
  stdout.writeln('Wrote $outputFile');
}
