import 'dart:convert';
import 'dart:io';

import 'package:dart_edge_tts/dart_edge_tts.dart';
import 'package:test/test.dart';

void main() {
  test('version matches upstream edge-tts 7.3.1', () {
    expect(version, '7.3.1');
    expect(versionInfo, [7, 3, 1]);
  });

  test('compose sorts and reindexes subtitles', () {
    final subs = [
      Subtitle(
        index: 2,
        start: Duration(seconds: 2),
        end: Duration(seconds: 3),
        content: 'two',
      ),
      Subtitle(
        index: 1,
        start: Duration(seconds: 1),
        end: Duration(seconds: 2),
        content: 'one',
      ),
    ];
    final srt = compose(subs);
    expect(srt, contains('1\n00:00:01,000 --> 00:00:02,000\none'));
    expect(srt, contains('2\n00:00:02,000 --> 00:00:03,000\ntwo'));
  });

  test('compose skips empty and invalid subtitles', () {
    final subs = [
      Subtitle(
        index: 1,
        start: Duration(seconds: 1),
        end: Duration(seconds: 2),
        content: '   ',
      ),
      Subtitle(
        index: 2,
        start: Duration(seconds: 5),
        end: Duration(seconds: 3),
        content: 'bad',
      ),
      Subtitle(
        index: 3,
        start: Duration(seconds: 3),
        end: Duration(seconds: 4),
        content: 'good',
      ),
    ];
    final srt = compose(subs);
    expect(srt, isNot(contains('bad')));
    expect(srt, contains('good'));
    expect(srt, contains('1\n00:00:03,000 --> 00:00:04,000\ngood'));
  });

  test('ProgressBar renders without error', () async {
    final sink = _BufferSink();
    final pb = ProgressBar('hello world this is a progress test',
        stream: sink, width: 40);
    pb.advance('hello');
    pb.setAudioTimeline(1000000);
    pb.addAudioBytes(1000);
    pb.render();
    pb.finish();
    expect(sink.contents, contains('%'));
  });
}

class _BufferSink implements IOSink {
  final StringBuffer _buf = StringBuffer();
  String get contents => _buf.toString();

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream<List<int>> stream) => stream.drain();
  @override
  Future close() => Future.value();
  @override
  Future get done => Future.value();
  @override
  void write(Object? obj) => _buf.write(obj);
  @override
  void writeAll(Iterable objects, [String sep = '']) => _buf.writeAll(objects, sep);
  @override
  void writeln([Object? obj = '']) => _buf.writeln(obj);
  @override
  void writeCharCode(int charCode) => _buf.writeCharCode(charCode);
  @override
  Future flush() => Future.value();
}
