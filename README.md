[English](README.md) | [简体中文](README.zh-CN.md)

# dart_edge_tts

Use Microsoft Edge's online text-to-speech service from Dart — no Windows or
Edge browser required. This is a faithful port of the Python
[`edge-tts`](https://github.com/rany2/edge-tts) package (currently aligned with
upstream `7.3.1`).

## Features

- Free, online neural TTS via Microsoft Edge's "Read Aloud" backend.
- Async-first Dart API: `Communicate`, `VoicesManager`, `SubMaker`.
- A `dart_edge_tts` command-line tool mirroring the Python CLI.
- List all available voices, pick by attribute (gender / locale / language).
- Adjust rate, volume and pitch.
- Generate `.srt` subtitles from word/sentence boundaries.
- Optional HTTP/WebSocket proxy support.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  dart_edge_tts:
    git:
      url: https://github.com/stardust1900/dart_edge_tts.git
      ref: master
```

> A Gitee mirror is also available at
> `https://gitee.com/wangyidao/dart-edge-tts.git`.

## Library usage

### Basic (save to file)

```dart
import 'package:dart_edge_tts/dart_edge_tts.dart';

Future<void> main() async {
  final communicate = Communicate(
    text: 'Hello, world!',
    voice: 'en-US-EmmaMultilingualNeural',
  );
  await communicate.save('hello.mp3');
}
```

### Streaming with subtitles

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_edge_tts/dart_edge_tts.dart';

Future<void> main() async {
  final communicate = Communicate(
    text: 'Hello World!',
    voice: 'en-GB-SoniaNeural',
  );
  final submaker = SubMaker();

  final raf = await File('test.mp3').open(mode: FileMode.write);
  try {
    await for (final chunk in communicate.stream()) {
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
  await File('test.srt').writeAsString(submaker.srt);
}
```

### Listing and selecting voices

```dart
import 'package:dart_edge_tts/dart_edge_tts.dart';

Future<void> main() async {
  final voices = await listVoices();
  print('${voices?.length} voices available');

  final manager = await VoicesManager.create();
  final spanishMales = manager.find(gender: 'Male', language: 'es');
  print(spanishMales.first.shortName);
}
```

### Rate / volume / pitch

```dart
final communicate = Communicate(
  text: 'Hello!',
  voice: 'en-US-EmmaMultilingualNeural',
  rate: '-50%',
  volume: '-50%',
  pitch: '-50Hz',
);
```

### Word-level subtitles

By default, subtitles are built from sentence boundaries. Pass
`boundary: 'WordBoundary'` to `Communicate` to get word-level cues instead:

```dart
final communicate = Communicate(
  text: 'Hello World!',
  voice: 'en-GB-SoniaNeural',
  boundary: 'WordBoundary',
);
```

> **Note on sync APIs:** the Python package offers `stream_sync()` /
> `save_sync()`. This Dart port exposes both the async API (`stream()` /
> `save()`) and thin synchronous-style wrappers (`streamSync()` /
> `saveSync()`). Prefer the async API; the wrappers run the same underlying
> stream inside a zone and are handy for simple scripts.

## CLI usage

```bash
# List voices
dart run dart_edge_tts:dart_edge_tts --list-voices

# Generate speech + subtitles
dart run dart_edge_tts:dart_edge_tts \
  --text "Hello, world!" \
  --write-media hello.mp3 \
  --write-subtitles hello.srt

# From a file, with a specific voice and lowered rate
dart run dart_edge_tts:dart_edge_tts \
  --file input.txt \
  --voice ar-EG-SalmaNeural \
  --rate=-50% \
  --write-media out.mp3

# Word-level subtitles
dart run dart_edge_tts:dart_edge_tts --text "Hi there" \
  --write-media a.mp3 --write-subtitles a.srt
```

### Options

| Flag | Description | Default |
| --- | --- | --- |
| `-t, --text` | Text to speak | |
| `-f, --file` | Read text from file (`-` for stdin) | |
| `-v, --voice` | Voice (e.g. `en-US-EmmaMultilingualNeural`) | `en-US-EmmaMultilingualNeural` |
| `-l, --list-voices` | List voices and exit | |
| `--rate` | Speech rate, e.g. `+0%`, `-50%` | `+0%` |
| `--volume` | Volume, e.g. `+0%`, `-50%` | `+0%` |
| `--pitch` | Pitch, e.g. `+0Hz`, `-50Hz` | `+0Hz` |
| `--write-media` | Write audio to file (`-` for stdout) | |
| `--write-subtitles` | Write subtitles to file (`-` for stderr) | |
| `--proxy` | HTTP/WebSocket proxy (e.g. `http://host:port`) | |
| `--no-progress` | Hide the progress bar on stderr | |
| `--version` | Print version | |

`--text` and `--file` are mutually exclusive; one of `--text`, `--file` or
`--list-voices` is required.

> Subtitles are written in SRT format. (The upstream Python package can also
> emit WebVTT; this port currently generates SRT only.)

## How it works

The package connects to Microsoft's Edge "Read Aloud" WebSocket endpoint,
sends a speech config + SSML, and streams back MP3 audio frames together with
word/sentence boundary metadata (used to build subtitles). Requests are
authenticated with a `Sec-MS-GEC` token derived from the current time, with
automatic clock-skew correction on `403` responses. See the Python project for
the original protocol research.

## License

MIT (same as the original Python project).
