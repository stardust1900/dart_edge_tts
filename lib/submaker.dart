import 'package:dart_edge_tts/srt_composer.dart';
import 'package:dart_edge_tts/typing.dart';

/// SubMaker is used to generate subtitles from WordBoundary and
/// SentenceBoundary messages.
class SubMaker {
  List<Subtitle> cues = [];
  TTSChunkType? type;

  /// Feed a WordBoundary or SentenceBoundary message to the SubMaker object.
  void feed(TTSChunk msg) {
    if (msg.type != TTSChunkType.wordBoundary &&
        msg.type != TTSChunkType.sentenceBoundary) {
      throw ArgumentError(
          "Invalid message type, expected 'WordBoundary' or 'SentenceBoundary'");
    }

    if (type == null) {
      type = msg.type;
    } else if (type != msg.type) {
      throw ArgumentError(
          "Expected message type '$type', but got '${msg.type}'");
    }

    cues.add(
      Subtitle(
        index: cues.length + 1,
        start: Duration(microseconds: msg.offset ~/ 10),
        end: Duration(microseconds: (msg.offset + msg.duration) ~/ 10),
        content: msg.text,
      ),
    );
  }

  /// Merge cues so each resulting cue contains at least [words] words.
  void mergeCues(int words) {
    if (words <= 0) {
      throw ArgumentError("Invalid number of words to merge, expected > 0");
    }

    if (cues.isEmpty) {
      return;
    }

    List<Subtitle> newCues = [];
    Subtitle currentCue = cues[0];

    for (var cue in cues.skip(1)) {
      if (currentCue.content.split(' ').length < words) {
        currentCue = Subtitle(
          index: currentCue.index,
          start: currentCue.start,
          end: cue.end,
          content: '${currentCue.content} ${cue.content}',
        );
      } else {
        newCues.add(currentCue);
        currentCue = cue;
      }
    }

    newCues.add(currentCue);
    cues = newCues;
  }

  /// Get the SRT formatted subtitles from the SubMaker object.
  String get srt => compose(cues);

  @override
  String toString() => srt;
}
