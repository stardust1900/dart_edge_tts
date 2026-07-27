/// Example: pick a voice dynamically by attribute, then synthesize.
import 'dart:io';
import 'dart:math';

import 'package:edge_tts/edge_tts.dart';

void main() async {
  const text = 'Hoy es un buen día.';
  const outputFile = 'example_es.mp3';

  final manager = await VoicesManager.create();
  final voices = manager.find(gender: 'Male', language: 'es');
  // Also supports Locale: manager.find(gender: 'Female', locale: 'es-AR')

  final rng = Random();
  final chosen = voices[rng.nextInt(voices.length)];
  print('Using voice: ${chosen['Name']}');

  final communicate = Communicate(text, chosen['Name'] as String);
  await communicate.save(outputFile);
  print('Wrote $outputFile');
  exit(0);
}
