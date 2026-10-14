/// Simple example to generate an audio file with randomized dynamic voice
/// selection based on attributes such as Gender, Language, or Locale.
///
/// Ported from edge-tts/examples/async_audio_gen_with_dynamic_voice_selection.py
library example.async_audio_gen_with_dynamic_voice_selection;

import 'dart:io';
import 'dart:math';

import 'package:dart_edge_tts/dart_edge_tts.dart';

const String text = 'Hoy es un buen día.';
const String outputFile = 'spanish.mp3';

Future<void> main() async {
  final voices = await VoicesManager.create();
  final matches = voices.find(gender: 'Male', language: 'es');
  // Also supports Locales:
  // final matches = voices.find(gender: 'Female', locale: 'es-AR');

  final rng = Random();
  final chosen = matches[rng.nextInt(matches.length)];
  stdout.writeln('Using voice: ${chosen.shortName}');

  final communicate = Communicate(text: text, voice: chosen.shortName);
  await communicate.save(outputFile);
  stdout.writeln('Wrote $outputFile');
}
