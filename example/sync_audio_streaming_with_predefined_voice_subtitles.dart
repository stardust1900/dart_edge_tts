/// Sync variant of the async .stream() method to get audio chunks and feed
/// them to SubMaker to generate subtitles.
///
/// Ported from
/// edge-tts/examples/sync_audio_streaming_with_predefined_voice_subtitles.py
library example.sync_audio_streaming_with_predefined_voice_subtitles;

import 'dart:io';
import 'dart:typed_data';

import 'package:dart_edge_tts/dart_edge_tts.dart';

const String text = 'Hello World!';
const String voice = 'en-GB-SoniaNeural';
const String outputFile = 'test.mp3';
const String srtFile = 'test.srt';

Future<void> main() async {
  final communicate = Communicate(text: text, voice: voice, boundary: 'WordBoundary');
  final submaker = SubMaker();

  final raf = await File(outputFile).open(mode: FileMode.write);
  try {
    await for (final chunk in communicate.streamSync()) {
      if (chunk.type == TTSChunkType.audio) {
        await raf.writeFrom(chunk.data as Uint8List);
      } else if (chunk.type == TTSChunkType.wordBoundary ||
          chunk.type == TTSChunkType.sentenceBoundary) {
        submaker.feed(chunk);
      }
    }
  } finally {
    await raf.close();
  }

  await File(srtFile).writeAsString(submaker.srt);
  stdout.writeln('Wrote $outputFile and $srtFile');
}
