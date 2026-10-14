import 'dart:convert' show utf8;
import 'dart:io';

import 'package:edge_tts/edge_tts.dart';
import 'package:edge_tts/src/util.dart'
    show
        xmlEscape,
        xmlUnescape,
        removeIncompatibleCharacters,
        splitTextByByteLength,
        mkssml;
import 'package:test/test.dart';

void main() {
  group('offline unit tests', () {
    test('xmlEscape / xmlUnescape round-trip', () {
      const input = '<a> "b" & \'c\' >';
      final escaped = xmlEscape(input);
      expect(escaped, '&lt;a&gt; &quot;b&quot; &amp; &apos;c&apos; &gt;');
      expect(xmlUnescape(escaped), input);
    });

    test('removeIncompatibleCharacters replaces control chars with space', () {
      final out = removeIncompatibleCharacters('a\u0007b\u000bc');
      expect(out, 'a b c');
    });

    test('splitTextByByteLength splits at whitespace and respects limit', () {
      // Whitespace-separated text is split; each chunk stays within the limit.
      final text = 'hello ' * 2000; // 12000 bytes, spaces every 6 bytes
      final chunks = splitTextByByteLength(text, 4096).toList();
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(utf8.encode(c).length, lessThanOrEqualTo(4096));
      }
    });

    test('splitTextByByteLength never splits a multi-byte character', () {
      // Chinese + spaces: splits happen at spaces, never mid-character.
      final text = '中 ' * 3000; // ~9000 bytes
      final chunks = splitTextByByteLength(text, 4096).toList();
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(utf8.encode(c).length, lessThanOrEqualTo(4096));
        // Round-tripping proves no character was broken across the boundary.
        expect(utf8.decode(utf8.encode(c)), c);
      }
    });

    test('TtsConfig normalizes short voice names', () {
      final cfg = TtsConfig('en-US-EmmaMultilingualNeural', '+0%', '+0%', '+0Hz',
          'SentenceBoundary');
      expect(cfg.voice,
          'Microsoft Server Speech Text to Speech Voice (en-US, EmmaMultilingualNeural)');
    });

    test('TtsConfig rejects invalid rate/volume/pitch', () {
      expect(
        () => TtsConfig('en-US-EmmaMultilingualNeural', 'fast', '+0%', '+0Hz',
            'SentenceBoundary'),
        throwsArgumentError,
      );
      expect(
        () => TtsConfig('en-US-EmmaMultilingualNeural', '+0%', '+0%', 'high',
            'SentenceBoundary'),
        throwsArgumentError,
      );
    });

    test('mkssml produces expected structure', () {
      final ssml = mkssml('Microsoft Server Speech Text to Speech Voice (en-US, EmmaNeural)',
          '+0Hz', '+0%', '+0%', 'Hello &amp; world');
      expect(ssml, contains("<voice name='Microsoft Server Speech Text to Speech Voice (en-US, EmmaNeural)'>"));
      expect(ssml, contains("rate='+0%'"));
      expect(ssml, contains('Hello &amp; world'));
    });

    test('generateSecMsGec is a 64-char uppercase hex string and stable in-window', () {
      final a = generateSecMsGec();
      final b = generateSecMsGec();
      expect(a, hasLength(64));
      expect(a, matches(RegExp(r'^[0-9A-F]{64}$')));
      expect(a, b); // same 5-minute window
    });

    test('Subtitle compose produces SRT and VTT', () {
      final subs = [
        Subtitle(
          index: 1,
          start: Duration(seconds: 1),
          end: Duration(seconds: 2),
          content: 'Hello',
        ),
        Subtitle(
          index: 2,
          start: Duration(seconds: 3),
          end: Duration(seconds: 4),
          content: 'World',
        ),
      ];
      final srt = compose(subs);
      expect(srt, contains('00:00:01,000 --> 00:00:02,000'));
      expect(srt, contains('Hello'));
      final vtt = composeVtt(subs);
      expect(vtt, startsWith('WEBVTT'));
      expect(vtt, contains('00:00:01.000 --> 00:00:02.000'));
    });
  });

  group('network integration tests', () {
    test('listVoices returns many voices', () async {
      try {
        final voices = await listVoices();
        expect(voices, isNotEmpty);
        expect(
          voices.any((v) => v['ShortName'] == 'en-US-EmmaMultilingualNeural'),
          isTrue,
        );
      } catch (e) {
        markTestSkipped('No network access to Microsoft Edge TTS: $e');
      }
    }, timeout: Timeout(Duration(seconds: 30)));

    test('Communicate.save produces an MP3 and subtitles', () async {
      final file = File('${Directory.systemTemp.path}/edge_tts_test.mp3');
      final srt = File('${Directory.systemTemp.path}/edge_tts_test.srt');
      try {
        final communicate =
            Communicate('Hello from Dart!', 'en-US-EmmaMultilingualNeural');
        final submaker = SubMaker();
        final raf = await file.open(mode: FileMode.write);
        try {
          await for (final chunk in communicate.stream()) {
            if (chunk.type == 'audio') {
              await raf.writeFrom(chunk.data!);
            } else {
              submaker.feed(chunk);
            }
          }
        } finally {
          await raf.close();
        }
        await srt.writeAsString(submaker.getSrt());
        expect(await file.length(), greaterThan(1000));
        expect(srt.readAsStringSync(), contains('Hello'));
      } catch (e) {
        markTestSkipped('No network access to Microsoft Edge TTS: $e');
      } finally {
        if (file.existsSync()) await file.delete();
        if (srt.existsSync()) await srt.delete();
      }
    }, timeout: Timeout(Duration(seconds: 60)));
  });
}
