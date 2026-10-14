/// SubMaker generates subtitles from WordBoundary/SentenceBoundary events.
///
/// Ported from Python `edge_tts/submaker.py`.
library;

import 'srt_composer.dart';
import 'communicate.dart' show TtsChunk;

/// Generates subtitles from WordBoundary/SentenceBoundary messages.
class SubMaker {
  /// The collected subtitle cues.
  final List<Subtitle> cues = [];

  String? _type;

  /// Feeds a WordBoundary or SentenceBoundary [msg] into the SubMaker.
  void feed(TtsChunk msg) {
    if (msg.type != 'WordBoundary' && msg.type != 'SentenceBoundary') {
      throw ArgumentError(
        "Invalid message type, expected 'WordBoundary' or 'SentenceBoundary'.",
      );
    }
    if (_type == null) {
      _type = msg.type;
    } else if (_type != msg.type) {
      throw ArgumentError(
        "Expected message type '$_type', but got '${msg.type}'.",
      );
    }
    cues.add(Subtitle(
      index: cues.length + 1,
      start: Duration(microseconds: (msg.offset! / 10).round()),
      end: Duration(microseconds: ((msg.offset! + msg.duration!) / 10).round()),
      content: msg.text!,
    ));
  }

  /// Returns the SRT formatted subtitles.
  String getSrt() => compose(cues);

  /// Returns the WebVTT formatted subtitles.
  String getVtt() => composeVtt(cues);

  @override
  String toString() => getSrt();
}
