/// Communicates with Microsoft Edge's online TTS service.
///
/// The [Communicate] class is the main entry point for end users. All other
/// classes/functions here are internal.
///
/// Ported from Python `edge_tts/communicate.py`.
library;

import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode, utf8;
import 'dart:io';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'constants.dart';
import 'drm.dart';
import 'exceptions.dart';
import 'util.dart';
import 'ws_connect.dart';

/// Internal TTS configuration for [Communicate].
class TtsConfig {
  /// Fully-qualified voice string sent to the service
  /// (e.g. `Microsoft Server Speech Text to Speech Voice (en-US, EmmaNeural)`).
  final String voice;

  /// Speech rate, e.g. `+0%`, `-50%`.
  final String rate;

  /// Volume, e.g. `+0%`, `-50%`.
  final String volume;

  /// Pitch, e.g. `+0Hz`, `-50Hz`.
  final String pitch;

  /// Boundary type used for subtitles/metadata: `WordBoundary` or
  /// `SentenceBoundary`.
  final String boundary;

  /// Creates a [TtsConfig], normalizing and validating the parameters.
  TtsConfig(
    String voice,
    this.rate,
    this.volume,
    this.pitch,
    this.boundary,
  ) : voice = _normalizeVoice(voice) {
    _validate();
  }

  static String _normalizeVoice(String voice) {
    final m = RegExp(r'^([a-z]{2,})-([A-Z]{2,})-(.+Neural)$').firstMatch(voice);
    if (m != null) {
      var lang = m.group(1)!;
      var region = m.group(2)!;
      var name = m.group(3)!;
      if (name.contains('-')) {
        final idx = name.indexOf('-');
        region = '$region-${name.substring(0, idx)}';
        name = name.substring(idx + 1);
      }
      return 'Microsoft Server Speech Text to Speech Voice ($lang-$region, $name)';
    }
    return voice;
  }

  void _validate() {
    if (!RegExp(r'^Microsoft Server Speech Text to Speech Voice \(.+,.+\)$')
        .hasMatch(voice)) {
      throw ArgumentError('Invalid voice: $voice');
    }
    _check('rate', rate, r'^[+-]\d+%$');
    _check('volume', volume, r'^[+-]\d+%$');
    _check('pitch', pitch, r'^[+-]\d+Hz$');
    if (boundary != 'WordBoundary' && boundary != 'SentenceBoundary') {
      throw ArgumentError(
        "boundary must be 'WordBoundary' or 'SentenceBoundary'",
      );
    }
  }

  static void _check(String name, String value, String pattern) {
    if (!RegExp(pattern).hasMatch(value)) {
      throw ArgumentError('Invalid $name: $value');
    }
  }
}

/// A single chunk yielded by [Communicate.stream].
///
/// For `type == 'audio'`, [data] holds the raw audio bytes. For
/// `type == 'WordBoundary'`/`'SentenceBoundary'`, [offset], [duration] and
/// [text] hold the metadata.
class TtsChunk {
  /// One of `audio`, `WordBoundary`, `SentenceBoundary`.
  final String type;

  /// Raw audio bytes (only for `type == 'audio'`).
  final List<int>? data;

  /// Start offset of the word/sentence, in 100-nanosecond ticks.
  final int? offset;

  /// Duration of the word/sentence, in 100-nanosecond ticks.
  final int? duration;

  /// The spoken text of the word/sentence.
  final String? text;

  /// Creates an audio chunk.
  TtsChunk.audio(this.data)
      : type = 'audio',
        offset = null,
        duration = null,
        text = null;

  /// Creates a boundary (WordBoundary/SentenceBoundary) chunk.
  TtsChunk.boundary(this.type, this.offset, this.duration, this.text)
      : data = null;
}

/// Communicates with Microsoft Edge's online text-to-speech service.
class Communicate {
  /// The validated TTS configuration.
  late final TtsConfig ttsConfig;

  /// The input text, split into <= 4096-byte chunks.
  late final List<String> texts;

  /// Optional proxy (e.g. `http://host:port`).
  final String? proxy;

  /// Socket connection timeout, in seconds.
  final int connectTimeout;

  /// Socket read timeout, in seconds.
  final int receiveTimeout;

  bool _streamWasCalled = false;
  int _offsetCompensation = 0;
  int _chunkAudioBytes = 0;
  int _cumulativeAudioBytes = 0;

  /// Creates a [Communicate] instance.
  ///
  /// [text] is the text to speak; [voice] selects the voice (e.g.
  /// `en-US-EmmaMultilingualNeural`). [rate], [volume] and [pitch] accept the
  /// same formats as the Python package (`+0%`, `-50%`, `+0Hz`, ...).
  Communicate(
    String text,
    String voice, {
    String rate = '+0%',
    String volume = '+0%',
    String pitch = '+0Hz',
    String boundary = 'SentenceBoundary',
    this.proxy,
    this.connectTimeout = 10,
    this.receiveTimeout = 60,
  }) {
    ttsConfig = TtsConfig(voice, rate, volume, pitch, boundary);
    final cleaned = removeIncompatibleCharacters(text);
    final escaped = xmlEscape(cleaned);
    texts = splitTextByByteLength(escaped, 4096).toList();
  }

  Map<String, dynamic> _wsHeaders() {
    final headers = <String, dynamic>{...wssHeaders}
      ..remove('Sec-WebSocket-Version');
    headers['Cookie'] = 'muid=${generateMuid()};';
    return headers;
  }

  String _configMessage() {
    final wordBoundary = ttsConfig.boundary == 'WordBoundary';
    final wd = wordBoundary ? 'true' : 'false';
    final sq = wordBoundary ? 'false' : 'true';
    return 'X-Timestamp:${dateToString()}\r\n'
        'Content-Type:application/json; charset=utf-8\r\n'
        'Path:speech.config\r\n\r\n'
        '{"context":{"synthesis":{"audio":{"metadataoptions":{'
        '"sentenceBoundaryEnabled":"$sq","wordBoundaryEnabled":"$wd"'
        '},'
        '"outputFormat":"audio-24khz-48kbitrate-mono-mp3"'
        '}}}}\r\n';
  }

  String _ssmlMessage(String partial) {
    return ssmlHeadersPlusData(
      _connectId(),
      dateToString(),
      mkssml(
        ttsConfig.voice,
        ttsConfig.pitch,
        ttsConfig.rate,
        ttsConfig.volume,
        partial,
      ),
    );
  }

  String _connectId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  bool _isForbidden(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('403') || s.contains('forbidden');
  }

  /// Streams audio and metadata from the service.
  ///
  /// Yields [TtsChunk]s. Throws [NoAudioReceived], [UnexpectedResponse],
  /// [UnknownResponse] or [WebSocketError] on failure.
  Stream<TtsChunk> stream() async* {
    if (_streamWasCalled) {
      throw StateError('stream can only be called once.');
    }
    _streamWasCalled = true;

    for (final partial in texts) {
      _chunkAudioBytes = 0;
      try {
        await for (final chunk in _streamOne(partial)) {
          yield chunk;
        }
      } catch (e) {
        if (!_isForbidden(e)) rethrow;
        final original = e;
        try {
          await syncClockFromServer(proxy);
        } catch (_) {
          throw original;
        }
        await for (final chunk in _streamOne(partial)) {
          yield chunk;
        }
      }
    }
  }

  Stream<TtsChunk> _streamOne(String partial) async* {
    var audioWasReceived = false;

    final url = Uri.parse(
      '$wssUrl&ConnectionId=${_connectId()}'
      '&Sec-MS-GEC=${generateSecMsGec()}'
      '&Sec-MS-GEC-Version=$secMsGecVersion',
    );

    final channel = await connectEdgeWebSocket(
      url.toString(),
      headers: _wsHeaders(),
      proxy: proxy,
      connectTimeout: Duration(seconds: connectTimeout),
    );

    try {
      channel.sink.add(_configMessage());
      channel.sink.add(_ssmlMessage(partial));

      await for (final message in channel.stream) {
        if (message is String) {
          final idx = message.indexOf('\r\n\r\n');
          final headerPart = idx < 0 ? message : message.substring(0, idx);
          final dataPart = idx < 0 ? '' : message.substring(idx + 4);
          final params = parseHttpLikeHeaders(headerPart);
          final path = params['Path'];

          if (path == 'audio.metadata') {
            final parsed = _parseMetadata(dataPart);
            if (parsed != null) {
              yield parsed;
            }
          } else if (path == 'turn.end') {
            _compensateOffset();
            break;
          } else if (path != 'response' && path != 'turn.start') {
            throw UnknownResponse('Unknown path received: $path');
          }
        } else if (message is List<int>) {
          final data = message;
          if (data.length < 2) {
            throw UnexpectedResponse(
              'We received a binary message, but it is missing the header length.',
            );
          }
          final headerLength = (data[0] << 8) | data[1];
          if (headerLength > data.length) {
            throw UnexpectedResponse(
              'The header length is greater than the length of the data.',
            );
          }
          final headerBytes = data.sublist(2, 2 + headerLength);
          final audioData = data.sublist(2 + headerLength);
          final params = parseHttpLikeHeaders(utf8.decode(headerBytes));

          if (params['Path'] != 'audio') {
            throw UnexpectedResponse(
              'Received binary message, but the path is not audio.',
            );
          }
          final contentType = params['Content-Type'];
          if (contentType != null && contentType != 'audio/mpeg') {
            throw UnexpectedResponse(
              'Received binary message, but with an unexpected Content-Type.',
            );
          }
          if (contentType == null) {
            if (audioData.isEmpty) continue;
            throw UnexpectedResponse(
              'Received binary message with no Content-Type, but with data.',
            );
          }
          if (audioData.isEmpty) {
            throw UnexpectedResponse(
              'Received binary message, but it is missing the audio data.',
            );
          }
          audioWasReceived = true;
          _chunkAudioBytes += audioData.length;
          yield TtsChunk.audio(audioData);
        }
      }
    } on WebSocketChannelException catch (e) {
      throw WebSocketError(e.message ?? e.toString());
    } finally {
      await channel.sink.close();
    }

    if (!audioWasReceived) {
      throw NoAudioReceived(
        'No audio was received. Please verify that your parameters are correct.',
      );
    }
  }

  TtsChunk? _parseMetadata(String dataPart) {
    final obj = jsonDecode(dataPart) as Map<String, dynamic>;
    final metas = (obj['Metadata'] as List<dynamic>?) ?? [];
    for (final metaObj in metas) {
      final meta = metaObj as Map<String, dynamic>;
      final type = meta['Type'] as String;
      if (type == 'WordBoundary' || type == 'SentenceBoundary') {
        final d = meta['Data'] as Map<String, dynamic>;
        final offset = (d['Offset'] as int) + _offsetCompensation;
        final duration = d['Duration'] as int;
        final text =
            xmlUnescape((d['text'] as Map<String, dynamic>)['Text'] as String);
        return TtsChunk.boundary(type, offset, duration, text);
      } else if (type == 'SessionEnd') {
        continue;
      } else {
        throw UnknownResponse('Unknown metadata type: $type');
      }
    }
    throw UnexpectedResponse('No WordBoundary/SentenceBoundary metadata found');
  }

  void _compensateOffset() {
    _cumulativeAudioBytes += _chunkAudioBytes;
    _offsetCompensation =
        _cumulativeAudioBytes * 8 * ticksPerSecond ~/ mp3BitrateBps;
    _chunkAudioBytes = 0;
  }

  /// Saves the audio to [audioFname]. If [metadataFname] is provided, the
  /// WordBoundary/SentenceBoundary metadata is written there as JSON lines.
  Future<void> save(
    String audioFname, {
    String? metadataFname,
  }) async {
    final raf = await File(audioFname).open(mode: FileMode.write);
    IOSink? metaOut;
    if (metadataFname != null) metaOut = File(metadataFname).openWrite();
    try {
      await for (final chunk in stream()) {
        if (chunk.type == 'audio') {
          await raf.writeFrom(chunk.data!);
        } else if (metaOut != null &&
            (chunk.type == 'WordBoundary' || chunk.type == 'SentenceBoundary')) {
          metaOut.writeln(jsonEncode({
            'type': chunk.type,
            'offset': chunk.offset,
            'duration': chunk.duration,
            'text': chunk.text,
          }));
        }
      }
    } finally {
      await raf.close();
      await metaOut?.close();
    }
  }

  /// Drains the stream into a list (the Dart-idiomatic equivalent of the
  /// Python `stream_sync`).
  Future<List<TtsChunk>> toList() => stream().toList();
}
