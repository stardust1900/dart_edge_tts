# edge_tts (Dart)

Use Microsoft Edge's online text-to-speech service from Dart — no Windows or
Edge browser required. This is a faithful port of the Python
[`edge-tts`](https://github.com/rany2/edge-tts) package.

## Features

- Free, online neural TTS via Microsoft Edge's "Read Aloud" backend.
- Async-first Dart API: `Communicate`, `VoicesManager`, `SubMaker`.
- A `edge_tts` command-line tool mirroring the Python CLI.
- List all available voices, pick by attribute (gender / locale / language).
- Adjust rate, volume and pitch.
- Generate `.srt` **and** `.vtt` subtitles from word/sentence boundaries.
- Optional HTTP/WebSocket proxy support.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
    edge_tts:
    git:
      url: https://gitee.com/wangyidao/dart-edge-tts.git
      ref: master
```
or

```yaml
dependencies:
    edge_tts:
    git:
      url: https://github.com/stardust1900/dart_edge_tts.git
      ref: master
```


## Library usage

### Basic (save to file)

```dart
import 'package:edge_tts/edge_tts.dart';

void main() async {
  final communicate = Communicate('Hello, world!', 'en-US-EmmaMultilingualNeural');
  await communicate.save('hello.mp3');
}
```

### Streaming with subtitles

```dart
import 'package:edge_tts/edge_tts.dart';

void main() async {
  final communicate = Communicate('Hello World!', 'en-GB-SoniaNeural');
  final submaker = SubMaker();

  final raf = await File('test.mp3').open(mode: FileMode.write);
  try {
    await for (final chunk in communicate.stream()) {
      if (chunk.type == 'audio') {
        await raf.writeFrom(chunk.data!);
      } else if (chunk.type == 'WordBoundary' || chunk.type == 'SentenceBoundary') {
        submaker.feed(chunk);
      }
    }
  } finally {
    await raf.close();
  }
  await File('test.srt').writeAsString(submaker.getSrt());
}
```

### Listing and selecting voices

```dart
import 'package:edge_tts/edge_tts.dart';

void main() async {
  final voices = await listVoices();
  print('${voices.length} voices available');

  final manager = await VoicesManager.create();
  final spanishMales = manager.find(gender: 'Male', language: 'es');
  print(spanishMales.first['Name']);
}
```

### Rate / volume / pitch

```dart
Communicate(
  'Hello!',
  'en-US-EmmaMultilingualNeural',
  rate: '-50%',
  volume: '-50%',
  pitch: '-50Hz',
);
```

### WebVTT subtitles (extra, not in the Python package)

```dart
await File('test.vtt').writeAsString(submaker.getVtt());
```

> **Note on sync APIs:** the Python package offers `stream_sync()` / `save_sync()`.
> Dart is single-threaded and async-first, so this port exposes `stream()`
> (a `Stream`) and `save()` (a `Future`). Use `await for` or
> `await communicate.stream().toList()` instead.

## CLI usage

```bash
# List voices
dart run edge_tts:edge_tts --list-voices

# Generate speech + subtitles
dart run edge_tts:edge_tts \
  --text "Hello, world!" \
  --write-media hello.mp3 \
  --write-subtitles hello.srt

# From a file, with a specific voice and lowered rate
dart run edge_tts:edge_tts \
  --file input.txt \
  --voice ar-EG-SalmaNeural \
  --rate=-50% \
  --write-media out.mp3

# Word-level subtitles
dart run edge_tts:edge_tts --text "Hi there" --boundary WordBoundary \
  --write-media a.mp3 --write-subtitles a.srt

# WebVTT output (extension-based)
dart run edge_tts:edge_tts --text "Hi there" --write-media a.mp3 --write-subtitles a.vtt
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
| `--boundary` | `WordBoundary` or `SentenceBoundary` | `SentenceBoundary` |
| `--write-media` | Write audio to file (`-` for stdout) | |
| `--write-subtitles` | Write subtitles to file (`-` for stderr; `.vtt` = WebVTT) | |
| `--proxy` | HTTP/WebSocket proxy (e.g. `http://host:port`) | |
| `-V, --version` | Print version | |
| `-h, --help` | Show help | |

`--text` and `--file` are mutually exclusive; one of `--text`, `--file` or
`--list-voices` is required.

## How it works

The package connects to Microsoft's Edge "Read Aloud" WebSocket endpoint,
sends a speech config + SSML, and streams back MP3 audio frames together with
word/sentence boundary metadata (used to build subtitles). Requests are
authenticated with a `Sec-MS-GEC` token derived from the current time, with
automatic clock-skew correction on `403` responses. See the Python project for
the original protocol research.

## License

MIT (same as the original Python project).
