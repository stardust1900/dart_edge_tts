#!/usr/bin/env dart
/// edge_tts command-line interface.
///
/// A faithful port of the Python `edge-tts` CLI.
///
/// Usage examples:
///   dart run edge_tts --text "Hello, world!" --write-media hello.mp3 --write-subtitles hello.srt
///   dart run edge_tts --list-voices
///   dart run edge_tts --voice ar-EG-SalmaNeural --file input.txt --write-media out.mp3
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:edge_tts/edge_tts.dart';

const String version = '7.2.8';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser(allowTrailingOptions: false);
  parser.addOption('text', abbr: 't', help: 'what TTS will say');
  parser.addOption('file',
      abbr: 'f', help: 'same as --text but read from file ("-" for stdin)');
  parser.addOption('voice',
      abbr: 'v',
      defaultsTo: defaultVoice,
      help: 'voice for TTS. Default: $defaultVoice');
  parser.addFlag('list-voices',
      abbr: 'l', negatable: false, help: 'lists available voices and exits');
  parser.addOption('rate', help: 'set TTS rate. Default +0%.', defaultsTo: '+0%');
  parser.addOption('volume',
      help: 'set TTS volume. Default +0%.', defaultsTo: '+0%');
  parser.addOption('pitch',
      help: 'set TTS pitch. Default +0Hz.', defaultsTo: '+0Hz');
  parser.addOption('boundary',
      allowed: ['WordBoundary', 'SentenceBoundary'],
      defaultsTo: 'SentenceBoundary',
      help: 'boundary type used for subtitles');
  parser.addOption('write-media',
      help: 'send media output to file instead of stdout ("-" for stdout)');
  parser.addOption('write-subtitles',
      help: 'send subtitle output to file ("-" for stderr, .vtt for WebVTT)');
  parser.addOption('proxy', help: 'use a proxy for TTS and voice list');
  parser.addFlag('version',
      abbr: 'V', negatable: false, help: 'show version and exit');
  parser.addFlag('help', abbr: 'h', negatable: false, help: 'show this help');

  late final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('error: $e');
    stderr.writeln(parser.usage);
    exit(1);
  }

  if (args['help'] as bool) {
    stdout.writeln(parser.usage);
    return;
  }
  if (args['version'] as bool) {
    stdout.writeln('edge_tts $version');
    return;
  }

  if (args['list-voices'] as bool) {
    await _printVoices(proxy: args['proxy'] as String?);
    return;
  }

  final textOpt = args['text'] as String?;
  final fileOpt = args['file'] as String?;
  if (textOpt != null && fileOpt != null) {
    stderr.writeln('error: --text and --file are mutually exclusive.');
    exit(1);
  }
  if (textOpt == null && fileOpt == null) {
    stderr.writeln(
      'error: one of --text, --file or --list-voices is required.\n',
    );
    stderr.writeln(parser.usage);
    exit(1);
  }

  String text;
  if (fileOpt != null) {
    if (fileOpt == '-' || fileOpt == '/dev/stdin') {
      text = await stdin.transform(utf8.decoder).join();
    } else {
      text = await File(fileOpt).readAsString();
    }
  } else {
    text = textOpt!;
  }

  final writeMedia = args['write-media'] as String?;
  final writeSubtitles = args['write-subtitles'] as String?;

  if (stdin.hasTerminal && stdout.hasTerminal && writeMedia == null) {
    stderr.writeln(
      'Warning: TTS output will be written to the terminal. '
      'Use --write-media to write to a file.\n'
      'Press Ctrl+C to cancel the operation. Press Enter to continue.',
    );
    stdin.readLineSync();
  }

  final communicate = Communicate(
    text,
    args['voice'] as String,
    rate: args['rate'] as String,
    volume: args['volume'] as String,
    pitch: args['pitch'] as String,
    boundary: args['boundary'] as String,
    proxy: args['proxy'] as String?,
  );
  final submaker = SubMaker();

  final IOSink audioOut =
      (writeMedia == null || writeMedia == '-') ? stdout : File(writeMedia).openWrite();

  IOSink? subOut;
  if (writeSubtitles != null) {
    subOut =
        (writeSubtitles == '-') ? stderr : File(writeSubtitles).openWrite();
  }

  try {
    await for (final chunk in communicate.stream()) {
      if (chunk.type == 'audio') {
        audioOut.add(chunk.data!);
      } else if (chunk.type == 'WordBoundary' || chunk.type == 'SentenceBoundary') {
        submaker.feed(chunk);
      }
    }
    if (subOut != null) {
      final isVtt = writeSubtitles != null &&
          writeSubtitles != '-' &&
          writeSubtitles.toLowerCase().endsWith('.vtt');
      subOut.writeln(isVtt ? submaker.getVtt() : submaker.getSrt());
    }
  } finally {
    if (writeMedia != null && writeMedia != '-') await audioOut.close();
    if (subOut != null && writeSubtitles != '-') await subOut.close();
  }
}

Future<void> _printVoices({String? proxy}) async {
  final voices = await listVoices(proxy: proxy);
  voices.sort((a, b) =>
      (a['ShortName'] as String).compareTo(b['ShortName'] as String));
  const headers = ['Name', 'Gender', 'ContentCategories', 'VoicePersonalities'];
  final rows = [
    for (final v in voices)
      [
        v['ShortName'] as String,
        v['Gender'] as String,
        (v['VoiceTag']['ContentCategories'] as List).join(', '),
        (v['VoiceTag']['VoicePersonalities'] as List).join(', '),
      ]
  ];
  _printTable(headers, rows);
}

void _printTable(List<String> headers, List<List<String>> rows) {
  final widths = <int>[
    for (var i = 0; i < headers.length; i++)
      headers[i].length +
          rows.fold(0, (m, r) => r[i].length > m ? r[i].length : m)
  ];
  String line(List<String> cells) =>
      cells.indexed.map((e) => e.$2.padRight(widths[e.$1])).join('  ').trimRight();
  stdout.writeln(line(headers));
  stdout.writeln('-' * widths.fold(0, (a, b) => a + b + 2));
  for (final r in rows) {
    stdout.writeln(line(r));
  }
}
