import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';

import 'constants.dart';
import 'data_classes.dart';
import 'drm.dart';
import 'exceptions.dart';
import 'typing.dart';

Map<String, dynamic> getHeadersAndData(Uint8List data, int headerLength) {
  final headers = <String, String>{};
  final headerBytes = data.sublist(0, headerLength);

  Uint8List bodyBytes = Uint8List(0);
  if (data.length > headerLength) {
    bodyBytes = data.sublist(headerLength);
  }
  final headerLines = utf8.decode(headerBytes).split("\r\n");
  for (final line in headerLines) {
    if (line.isNotEmpty) {
      final parts = line.split(":");
      if (parts.length == 2) {
        headers[parts[0].trim()] = parts[1].trim();
      }
    }
  }
  return {'headers': headers, 'data': bodyBytes as dynamic};
}

String removeIncompatibleCharacters(String input) {
  final chars = input.runes.map((rune) {
    final code = rune;
    if ((0 <= code && code <= 8) ||
        (11 <= code && code <= 12) ||
        (14 <= code && code <= 31)) {
      return " ";
    }
    return String.fromCharCode(code);
  }).join();

  return chars;
}

String connectId() {
  return Uuid().v4().replaceAll("-", "");
}

int _findLastNewlineOrSpaceWithinLimit(Uint8List text, int limit) {
  int splitAt = -1;
  for (int i = limit - 1; i >= 0; i--) {
    if (text[i] == 0x0A) {
      splitAt = i;
      break;
    }
  }
  if (splitAt < 0) {
    for (int i = limit - 1; i >= 0; i--) {
      if (text[i] == 0x20) {
        splitAt = i;
        break;
      }
    }
  }
  return splitAt;
}

int _findSafeUtf8SplitPoint(Uint8List segment) {
  int splitAt = segment.length;
  while (splitAt > 0) {
    try {
      utf8.decode(segment.sublist(0, splitAt));
      return splitAt;
    } on FormatException {
      splitAt -= 1;
    }
  }
  return splitAt;
}

int _adjustSplitPointForXmlEntity(Uint8List text, int splitAt) {
  int cur = splitAt;
  while (cur > 0 && text.sublist(0, cur).contains(0x26)) {
    int amp = -1;
    for (int i = cur - 1; i >= 0; i--) {
      if (text[i] == 0x26) {
        amp = i;
        break;
      }
    }
    if (amp < 0) {
      break;
    }
    bool terminated = false;
    for (int i = amp; i < cur; i++) {
      if (text[i] == 0x3B) {
        terminated = true;
        break;
      }
    }
    if (terminated) {
      break;
    }
    cur = amp;
  }
  return cur;
}

Iterable<Uint8List> splitTextByByteLength(String text, int byteLength) sync* {
  Uint8List data = Uint8List.fromList(utf8.encode(text));
  if (byteLength <= 0) {
    throw ArgumentError("byte_length 必须大于 0");
  }
  while (data.length > byteLength) {
    int splitAt = _findLastNewlineOrSpaceWithinLimit(data, byteLength);
    if (splitAt < 0) {
      splitAt = _findSafeUtf8SplitPoint(data);
    }
    splitAt = _adjustSplitPointForXmlEntity(data, splitAt);
    if (splitAt < 0) {
      throw ArgumentError("最大字节长度太小或文本格式无效");
    }
    final chunk = data.sublist(0, splitAt);
    final chunkStr = utf8.decode(chunk).trim();
    final chunkBytes = Uint8List.fromList(utf8.encode(chunkStr));
    if (chunkBytes.isNotEmpty) {
      yield chunkBytes;
    }
    data = data.sublist(splitAt > 0 ? splitAt : 1);
  }
  final remaining = utf8.decode(data).trim();
  if (remaining.isNotEmpty) {
    yield Uint8List.fromList(utf8.encode(remaining));
  }
}

String mkssml(TTSConfig tc, String escapedText) {
  return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>"
      "<voice name='${tc.voice}'>"
      "<prosody pitch='${tc.pitch}' rate='${tc.rate}' volume='${tc.volume}'>"
      "$escapedText"
      "</prosody>"
      "</voice>"
      "</speak>";
}

String dateToString() {
  DateTime now = DateTime.now().toUtc();
  DateFormat dateFormat = DateFormat(
      "EEE MMM dd yyyy HH:mm:ss 'GMT+0000' '(Coordinated Universal Time)'");
  return dateFormat.format(now);
}

String ssmlHeadersPlusData(String requestId, String timestamp, String ssml) {
  return "X-RequestId:$requestId\r\n"
          "Content-Type:application/ssml+xml\r\n"
          "X-Timestamp:${timestamp}Z\r\n"
          "Path:ssml\r\n\r\n"
          "$ssml"
      .trim();
}

String _unescapeXml(String s) {
  return s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
}

class Communicate {
  late final TTSConfig ttsConfig;
  late final Iterable<Uint8List> texts;
  final String? proxy;
  final Duration connectTimeout;
  final Duration receiveTimeout;
  final http.Client? connector;
  late final CommunicateState state;

  static String escape(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  Communicate({
    required String text,
    String voice = defaultVoice,
    String rate = '+0%',
    String volume = '+0%',
    String pitch = '+0Hz',
    String boundary = 'SentenceBoundary',
    this.connector,
    this.proxy,
    int? connectTimeoutSeconds = 10,
    int? receiveTimeoutSeconds = 60,
  })  : connectTimeout = Duration(seconds: connectTimeoutSeconds ?? 10),
        receiveTimeout = Duration(seconds: receiveTimeoutSeconds ?? 60) {
    final ttsConfig_ =
        TTSConfig.validate(voice, rate, volume, pitch, boundary);

    if (proxy != null && proxy!.isEmpty) {
      throw ArgumentError("proxy must be a non-empty string");
    } else if (proxy != null && proxy is! String) {
      throw ArgumentError("proxy must be a string");
    }
    if (connectTimeout <= Duration.zero) {
      throw ArgumentError("connect_timeout must be a positive integer");
    }
    if (receiveTimeout <= Duration.zero) {
      throw ArgumentError("receive_timeout must be a positive integer");
    }

    final texts_ =
        _initializeTexts(text, ttsConfig_);
    final state_ = CommunicateState(
      partialText: texts_.first,
      offsetCompensation: 0,
      lastDurationOffset: 0,
      streamWasCalled: false,
    );

    ttsConfig = ttsConfig_;
    texts = texts_;
    state = state_;
  }

  static Iterable<Uint8List> _initializeTexts(
      String text, TTSConfig ttsConfig) {
    final escapedText =
        escape(removeIncompatibleCharacters(text));
    return splitTextByByteLength(escapedText, 4096);
  }

  TTSChunk _parseMetadata(Uint8List data) {
    final jsonString = utf8.decode(data);
    final jsonData = jsonDecode(jsonString);
    final metadata = jsonData['Metadata'] as List<dynamic>;

    final Map<String, TTSChunkType> typeMapping = {
      'WordBoundary': TTSChunkType.wordBoundary,
      'SentenceBoundary': TTSChunkType.sentenceBoundary,
    };

    for (var metaObj in metadata) {
      final metaTypeStr = metaObj['Type'] as String?;
      if (metaTypeStr == "SessionEnd") {
        continue;
      }
      if (metaTypeStr == null) {
        throw Exception("Invalid metadata format: Type is missing");
      }
      final metaType = typeMapping[metaTypeStr];
      if (metaType == null) {
        throw UnexpectedResponse("Invalid metadata type: $metaTypeStr");
      }

      if (metaType == TTSChunkType.wordBoundary ||
          metaType == TTSChunkType.sentenceBoundary) {
        final d = metaObj['Data'] as Map<String, dynamic>?;
        if (d == null) {
          throw UnexpectedResponse("Invalid metadata format: Data is missing");
        }

        final currentOffset =
            (d['Offset'] as int? ?? 0) + state.offsetCompensation;
        final currentDuration = d['Duration'] as int? ?? 0;
        final textRaw = d['text']['Text'] as String?;

        if (textRaw == null) {
          throw UnexpectedResponse("Invalid metadata format: Text is missing");
        }
        return TTSChunk(
          type: metaType,
          offset: currentOffset,
          duration: currentDuration,
          text: _unescapeXml(textRaw),
        );
      }
      throw UnexpectedResponse("Unknown metadata type: $metaType");
    }
    throw UnexpectedResponse("No WordBoundary metadata found");
  }

  void _compensateOffset() {
    state.cumulativeAudioBytes += state.chunkAudioBytes;
    state.offsetCompensation =
        state.cumulativeAudioBytes * 8 * ticksPerSecond ~/ mp3BitrateBps;
    state.chunkAudioBytes = 0;
  }

  Stream<TTSChunk> _stream() async* {
    final sslContext = SecurityContext.defaultContext;

    final webSocketUrl = Uri.parse(
      "$wssUrl&Sec-MS-GEC=${DRM.generateSecMsGec()}"
      "&Sec-MS-GEC-Version=$secMsGecVersion"
      "&ConnectionId=${connectId()}",
    );

    final client = HttpClient(context: sslContext);
    client.userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
        " AppleWebKit/537.36 (KHTML, like Gecko)"
        " Chrome/$chromiumMajorVersion.0.0.0 Safari/537.36"
        " Edg/$chromiumMajorVersion.0.0.0";
    final webSocket = IOWebSocketChannel.connect(webSocketUrl,
        customClient: client, headers: DRM.headersWithMuid(wssHeaders));

    try {
      final wordBoundary = ttsConfig.boundary == 'WordBoundary';
      final wd = wordBoundary ? 'true' : 'false';
      final sq = wordBoundary ? 'false' : 'true';
      webSocket.sink.add(
        "X-Timestamp:${dateToString()}\r\n"
        "Content-Type:application/json; charset=utf-8\r\n"
        "Path:speech.config\r\n\r\n"
        '{"context":{"synthesis":{"audio":{"metadataoptions":{'
        '"sentenceBoundaryEnabled":"$sq","wordBoundaryEnabled":"$wd"},'
        '"outputFormat":"audio-24khz-48kbitrate-mono-mp3"'
        "}}}}\r\n",
      );

      webSocket.sink.add(
        ssmlHeadersPlusData(
          connectId(),
          dateToString(),
          mkssml(ttsConfig, utf8.decode(state.partialText)),
        ),
      );
      var audioWasReceived = false;
      await for (final message in webSocket.stream) {
        if (webSocket.closeCode != null) {
          break;
        }
        if (message is String) {
          final encodedData = utf8.encode(message);
          final headerEndIndex = message.indexOf("\r\n\r\n");
          final headersAndData =
              getHeadersAndData(encodedData, headerEndIndex);
          final Map<String, String> headers = headersAndData["headers"]!;
          final data = headersAndData["data"] as Uint8List;

          final path = headers["Path"];
          if (path == "audio.metadata") {
            final parsedMetadata = _parseMetadata(data);
            yield parsedMetadata;
            state.lastDurationOffset =
                parsedMetadata.offset + parsedMetadata.duration;
          } else if (path == "turn.end") {
            _compensateOffset();
            break;
          } else if (path != "response" && path != "turn.start") {
            throw UnknownResponse("Unknown path received");
          }
        } else if (message is Uint8List) {
          if (message.length < 2) {
            throw UnexpectedResponse(
                "We received a binary message, but it is missing the header length.");
          }
          final headerLengthBytes = message.sublist(0, 2);
          final headerLength =
              ByteData.sublistView(headerLengthBytes).getInt16(0, Endian.big);
          if (headerLength > message.length) {
            throw UnexpectedResponse(
                "The header length is greater than the length of the data.");
          }
          final headersAndData =
              getHeadersAndData(message.sublist(2), headerLength);
          final Map<String, String> headers = headersAndData["headers"]!;
          final data = headersAndData["data"] as Uint8List;

          final path = headers["Path"];
          if (path != "audio") {
            throw UnexpectedResponse(
                "Received binary message, but the path is not audio.");
          }

          final contentType = headers["Content-Type"];
          if (contentType == null) {
            if (data.isNotEmpty) {
              throw UnexpectedResponse(
                  "Received binary message with no Content-Type, but with data.");
            }
            continue;
          } else if (contentType != "audio/mpeg") {
            throw UnexpectedResponse(
                "Received binary message with an unexpected Content-Type.");
          }

          if (data.isEmpty) {
            throw UnexpectedResponse(
                "Received binary message, but it is missing the audio data.");
          }

          audioWasReceived = true;
          state.chunkAudioBytes += data.length;
          yield TTSChunk(
            type: TTSChunkType.audio,
            data: data,
            duration: 0,
            offset: 0,
            text: '',
          );
        } else {
          throw WebSocketError(message.error.toString());
        }
      }
      if (!audioWasReceived) {
        throw NoAudioReceived(
            "No audio was received. Please verify that your parameters are correct.");
      }
    } catch (e) {
      rethrow;
    } finally {
      await webSocket.sink.close();
    }
  }

  Stream<TTSChunk> stream() async* {
    if (state.streamWasCalled) {
      throw StateError("stream can only be called once.");
    }
    state.streamWasCalled = true;
    for (final partialText in texts) {
      state.partialText = partialText;
      state.chunkAudioBytes = 0;
      try {
        await for (final message in _stream()) {
          yield message;
        }
      } on WebSocketException catch (e) {
        // 握手 403 通常源于服务端时钟偏移；与 Python 一致重试一次，
        // _stream() 内部会重新生成 Sec-MS-GEC token。WebSocket 升级不暴露
        // 响应头，无法像 listVoices 那样用 Date 头做精确时钟偏移校正。
        if (!e.toString().contains("403")) {
          rethrow;
        }
        state.chunkAudioBytes = 0;
        await for (final message in _stream()) {
          yield message;
        }
      }
    }
  }

  Future<void> save(String audioFname, [String? metadataFname]) async {
    final audioFile = File(audioFname);
    final audioSink = audioFile.openWrite();
    IOSink? metadataSink;
    if (metadataFname != null) {
      metadataSink = File(metadataFname).openWrite(encoding: utf8);
    }

    try {
      await for (final message in stream()) {
        if (message.type == TTSChunkType.audio) {
          if ((message.data as Uint8List).isNotEmpty) {
            audioSink.add(message.data as Uint8List);
          }
        } else if (metadataSink != null &&
            (message.type == TTSChunkType.wordBoundary ||
                message.type == TTSChunkType.sentenceBoundary)) {
          metadataSink.write(jsonEncode(message.toMap()));
          metadataSink.write('\n');
        }
      }
    } finally {
      await audioSink.close();
      if (metadataSink != null) {
        await metadataSink.close();
      }
    }
  }

  Stream<TTSChunk> streamSync() async* {
    final controller = StreamController<TTSChunk>();
    final completer = Completer<void>();

    void listenToStream() async {
      try {
        await for (final message in stream()) {
          controller.add(message);
        }
        controller.close();
        completer.complete();
      } catch (e) {
        controller.addError(e);
        controller.close();
        completer.completeError(e);
      }
    }

    Future.microtask(listenToStream);

    yield* controller.stream;
  }

  void saveSync(String audioFname, [String? metadataFname]) {
    runZonedGuarded(() async {
      await save(audioFname, metadataFname);
    }, (error, stackTrace) {
      print('Error during save: $error\n$stackTrace');
    });
  }
}
