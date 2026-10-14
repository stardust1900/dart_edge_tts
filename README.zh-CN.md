[English](README.md) | [简体中文](README.zh-CN.md)

# dart_edge_tts

通过 Dart 使用微软 Edge 的在线文字转语音服务 —— 无需 Windows 或 Edge 浏览器。
这是 Python 项目 [`edge-tts`](https://github.com/rany2/edge-tts) 的忠实移植
（当前与上游 `7.3.1` 对齐）。

## 特性

- 免费、在线的神经网络 TTS，基于微软 Edge 的“朗读”后端。
- 异步优先的 Dart API：`Communicate`、`VoicesManager`、`SubMaker`。
- 提供与 Python CLI 对应的 `dart_edge_tts` 命令行工具。
- 列出所有可用音色，并按属性（性别 / 区域 / 语言）筛选。
- 可调节语速、音量和音高。
- 基于词 / 句边界生成 `.srt` 字幕。
- 支持可选的 HTTP/WebSocket 代理。

## 安装

在 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  dart_edge_tts:
    git:
      url: https://github.com/stardust1900/dart_edge_tts.git
      ref: master
```

> 也可使用 Gitee 镜像：
> `https://gitee.com/wangyidao/dart-edge-tts.git`。

## 库用法

### 基础（保存为文件）

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

### 流式合成并生成字幕

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

### 列出并筛选音色

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

### 语速 / 音量 / 音高

```dart
final communicate = Communicate(
  text: 'Hello!',
  voice: 'en-US-EmmaMultilingualNeural',
  rate: '-50%',
  volume: '-50%',
  pitch: '-50Hz',
);
```

### 词级字幕

默认情况下，字幕基于句边界生成。给 `Communicate` 传入 `boundary: 'WordBoundary'`
可改为词级字幕：

```dart
final communicate = Communicate(
  text: 'Hello World!',
  voice: 'en-GB-SoniaNeural',
  boundary: 'WordBoundary',
);
```

> **关于同步 API：** Python 包提供了 `stream_sync()` / `save_sync()`。本 Dart
> 移植同时提供了异步 API（`stream()` / `save()`）和轻量的“同步风格”包装
> （`streamSync()` / `saveSync()`）。推荐优先使用异步 API；包装器只是把同一底层
> 流放到一个 zone 中执行，方便简单脚本使用。

## 命令行用法

```bash
# 列出音色
dart run dart_edge_tts:dart_edge_tts --list-voices

# 合成语音 + 字幕
dart run dart_edge_tts:dart_edge_tts \
  --text "Hello, world!" \
  --write-media hello.mp3 \
  --write-subtitles hello.srt

# 从文件读取，指定音色并降低语速
dart run dart_edge_tts:dart_edge_tts \
  --file input.txt \
  --voice ar-EG-SalmaNeural \
  --rate=-50% \
  --write-media out.mp3

# 词级字幕
dart run dart_edge_tts:dart_edge_tts --text "Hi there" \
  --write-media a.mp3 --write-subtitles a.srt
```

### 选项

| 选项 | 说明 | 默认值 |
| --- | --- | --- |
| `-t, --text` | 待合成的文本 | |
| `-f, --file` | 从文件读取文本（`-` 表示 stdin） | |
| `-v, --voice` | 音色（如 `en-US-EmmaMultilingualNeural`） | `en-US-EmmaMultilingualNeural` |
| `-l, --list-voices` | 列出音色并退出 | |
| `--rate` | 语速，如 `+0%`、`-50%` | `+0%` |
| `--volume` | 音量，如 `+0%`、`-50%` | `+0%` |
| `--pitch` | 音高，如 `+0Hz`、`-50Hz` | `+0Hz` |
| `--write-media` | 将音频写入文件（`-` 表示 stdout） | |
| `--write-subtitles` | 将字幕写入文件（`-` 表示 stderr） | |
| `--proxy` | HTTP/WebSocket 代理（如 `http://host:port`） | |
| `--no-progress` | 不在 stderr 显示进度条 | |
| `--version` | 打印版本号 | |

`--text` 与 `--file` 互斥；必须提供 `--text`、`--file` 或 `--list-voices` 之一。

> 字幕以 SRT 格式写入。（上游 Python 包还能输出 WebVTT；本移植目前仅生成 SRT。）

## 工作原理

本包连接到微软 Edge“朗读”的 WebSocket 端点，发送语音配置与 SSML，并流式返回
MP3 音频帧，以及用于生成字幕的词 / 句边界元数据。请求使用基于当前时间派生的
`Sec-MS-GEC` 令牌进行鉴权，并在收到 `403` 响应时自动校正时钟偏差。协议研究详见
Python 原项目。

## 许可证

MIT（与 Python 原项目一致）。
