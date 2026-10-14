import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:dart_edge_tts/constants.dart';
import 'package:dart_edge_tts/dart_edge_tts.dart';

Future<void> _printVoices() async {
  final voices = await listVoices();
  if (voices == null) {
    stderr.writeln('Failed to fetch voices.');
    return;
  }
  voices.sort((a, b) => a.shortName.compareTo(b.shortName));
  const headers = ['Name', 'Gender', 'ContentCategories', 'VoicePersonalities'];
  final rows = voices.map((voice) => [
        voice.shortName,
        voice.gender,
        voice.voiceTag.contentCategories.map((c) => c.name).join(', '),
        voice.voiceTag.voicePersonalities.map((p) => p.name).join(', '),
      ]);
  _printTable(headers, rows);
}

void _printTable(List<String> headers, Iterable<List<String>> rows) {
  final widths = <int>[];
  for (var i = 0; i < headers.length; i++) {
    var w = headers[i].length;
    for (final row in rows) {
      w = w > row[i].length ? w : row[i].length;
    }
    widths.add(w);
  }
  String line(List<String> cells) {
    final buf = StringBuffer();
    for (var i = 0; i < cells.length; i++) {
      buf.write(cells[i].padRight(widths[i]));
      if (i < cells.length - 1) buf.write('  ');
    }
    return buf.toString();
  }

  print(line(headers));
  for (final row in rows) {
    print(line(row));
  }
}

bool _shouldShowProgress(String? writeSubtitles, bool noProgress) {
  if (noProgress) return false;
  if (writeSubtitles == '-') return false;
  return stderr.hasTerminal;
}

Future<void> _runTts(String text, String voice, String rate, String volume,
    String pitch, String? proxy, String? writeMedia, String? writeSubtitles,
    {bool noProgress = false}) async {
  if (stdout.hasTerminal && writeMedia == null) {
    stderr.writeln(
        'Warning: TTS output will be written to the terminal. '
        'Use --write-media to write to a file.');
  }

  final communicate = Communicate(
    text: text,
    voice: voice,
    rate: rate,
    volume: volume,
    pitch: pitch,
    proxy: proxy,
  );
  final submaker = SubMaker();
  final progress =
      _shouldShowProgress(writeSubtitles, noProgress) ? ProgressBar(text) : null;

  IOSink? audioFile;
  if (writeMedia != null && writeMedia != '-') {
    audioFile = File(writeMedia).openWrite();
  } else {
    audioFile = stdout;
  }

  IOSink? subFile;
  if (writeSubtitles != null && writeSubtitles != '-') {
    subFile = File(writeSubtitles).openWrite();
  } else if (writeSubtitles == '-') {
    subFile = stderr;
  }

  try {
    await for (final chunk in communicate.stream()) {
      if (chunk.type == TTSChunkType.audio) {
        audioFile.add(chunk.data as Uint8List);
        progress?.addAudioBytes((chunk.data as Uint8List).length);
      } else if (chunk.type == TTSChunkType.wordBoundary ||
          chunk.type == TTSChunkType.sentenceBoundary) {
        submaker.feed(chunk);
        progress?.advance(chunk.text);
        progress?.setAudioTimeline(chunk.offset + chunk.duration);
      }
      progress?.render();
    }
    progress?.finish();
    subFile?.write(submaker.srt);
  } finally {
    progress?.close();
    if (audioFile != stdout) {
      await audioFile.close();
    }
    if (subFile != null && subFile != stderr) {
      await subFile.close();
    }
  }
}

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('text', abbr: 't', help: 'what TTS will say')
    ..addOption('file', abbr: 'f', help: 'same as --text but read from file')
    ..addOption('voice',
        abbr: 'v',
        help: 'voice for TTS. Default: $defaultVoice',
        defaultsTo: defaultVoice)
    ..addFlag('list-voices',
        abbr: 'l', help: 'lists available voices and exits', negatable: false)
    ..addOption('rate', help: 'set TTS rate. Default +0%.', defaultsTo: '+0%')
    ..addOption('volume',
        help: 'set TTS volume. Default +0%.', defaultsTo: '+0%')
    ..addOption('pitch',
        help: 'set TTS pitch. Default +0Hz.', defaultsTo: '+0Hz')
    ..addOption('write-media',
        help: 'send media output to file instead of stdout')
    ..addOption('write-subtitles',
        help: 'send subtitle output to provided file instead of stderr')
    ..addOption('proxy', help: 'use a proxy for TTS and voice list.')
    ..addFlag('no-progress',
        help: 'do not show the progress bar on stderr', negatable: false)
    ..addFlag('version',
        help: 'show the version and exit', negatable: false);

  final results = parser.parse(arguments);

  if (results['version'] as bool) {
    print('dart_edge_tts $version');
    return;
  }

  final text = results['text'] as String?;
  final file = results['file'] as String?;
  final listVoicesFlag = results['list-voices'] as bool;

  if (listVoicesFlag) {
    await _printVoices();
    return;
  }

  String? sourceText = text;
  if (file != null) {
    if (text != null) {
      stderr.writeln('Error: --text and --file are mutually exclusive.');
      exit(2);
    }
    if (file == '-' || file == '/dev/stdin') {
      sourceText = await stdin.transform(utf8.decoder).join();
    } else {
      sourceText = await File(file).readAsString();
    }
  }

  if (sourceText == null || sourceText.isEmpty) {
    stderr.writeln('Error: provide --text, --file, or --list-voices.');
    exit(2);
  }

  await _runTts(
    sourceText,
    results['voice'] as String,
    results['rate'] as String,
    results['volume'] as String,
    results['pitch'] as String,
    results['proxy'] as String?,
    results['write-media'] as String?,
    results['write-subtitles'] as String?,
    noProgress: results['no-progress'] as bool,
  );
}
