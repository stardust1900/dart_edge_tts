/// Example: stream audio and build SRT subtitles from sentence boundaries.
import 'dart:io';

import 'package:edge_tts/edge_tts.dart';

void main() async {
  const text = 'Hello World! This is a demonstration of subtitles.';
  const voice = 'en-GB-SoniaNeural';
  const outputFile = 'example_sub.mp3';
  const srtFile = 'example_sub.srt';

  final communicate = Communicate(text, voice);
  final submaker = SubMaker();

  final raf = await File(outputFile).open(mode: FileMode.write);
  try {
    await for (final chunk in communicate.stream()) {
      if (chunk.type == 'audio') {
        await raf.writeFrom(chunk.data!);
      } else if (chunk.type == 'WordBoundary' ||
          chunk.type == 'SentenceBoundary') {
        submaker.feed(chunk);
      }
    }
  } finally {
    await raf.close();
  }

  await File(srtFile).writeAsString(submaker.getSrt());
  print('Wrote $outputFile and $srtFile');
  exit(0);
}
