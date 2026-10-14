/// A tiny library for composing SRT files.
///
/// Ported from https://github.com/cdown/srt (by Christopher Down, MIT) and
/// adapted by edge-tts. Parsing and subtitle-modifying functionality were
/// removed; only what edge-tts needs (sorting, reindexing, making content
/// legal, and serialising to SRT) is kept.
library dart_edge_tts.srt_composer;

import 'dart:core';

/// Matches two or more consecutive newlines.
final RegExp _multiWsRegex = RegExp(r"\n\n+");

/// A single subtitle cue. Subtitles are ordered by start time by default.
class Subtitle implements Comparable<Subtitle> {
  /// The SRT index for this subtitle (index 0 when not provided on write).
  int? index;

  /// The time that the subtitle should start being shown.
  final Duration start;

  /// The time that the subtitle should stop being shown.
  final Duration end;

  /// The subtitle content (should use "\n", never OS-specific separators).
  final String content;

  Subtitle({
    required this.index,
    required this.start,
    required this.end,
    required this.content,
  });

  @override
  int compareTo(Subtitle other) {
    final c = start.compareTo(other.start);
    if (c != 0) return c;
    final c2 = end.compareTo(other.end);
    if (c2 != 0) return c2;
    return (index ?? 0).compareTo(other.index ?? 0);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Subtitle &&
          index == other.index &&
          start == other.start &&
          end == other.end &&
          content == other.content;

  @override
  int get hashCode => Object.hash(index, start, end, content);

  @override
  String toString() => toSrt();

  /// Convert this subtitle to an SRT block.
  ///
  /// [eol] is the line separator (defaults to "\n").
  String toSrt({String? eol}) {
    final outputContent = makeLegalContent(content);
    final e = eol ?? "\n";
    final renderedContent =
        eol == null ? outputContent : outputContent.replaceAll("\n", e);
    return "${index ?? 0}$e"
        "${timedeltaToSrtTimestamp(start)} --> "
        "${timedeltaToSrtTimestamp(end)}$e"
        "$renderedContent$e$e";
  }
}

/// Remove illegal content from a content block (blank lines / leading or
/// trailing blank lines).
String makeLegalContent(String content) {
  // Optimisation: usually the content is already legal, so skip the work.
  if (content.isNotEmpty &&
      !content.startsWith("\n") &&
      !content.contains("\n\n")) {
    return content;
  }
  final stripped = content.replaceAll(RegExp(r"^\n+|\n+$"), "");
  return stripped.replaceAll(_multiWsRegex, "\n");
}

/// Convert a [Duration] to an SRT timestamp (HH:MM:SS,mmm).
String timedeltaToSrtTimestamp(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final remainder = totalSeconds % 3600;
  final minutes = remainder ~/ 60;
  final seconds = remainder % 60;
  final millis = duration.inMilliseconds % 1000;
  return "${hours.toString().padLeft(2, '0')}:"
      "${minutes.toString().padLeft(2, '0')}:"
      "${seconds.toString().padLeft(2, '0')},"
      "${millis.toString().padLeft(3, '0')}";
}

bool _shouldSkipSub(Subtitle subtitle) {
  if (subtitle.content.trim().isEmpty) {
    return true; // No content
  }
  if (subtitle.start < Duration.zero) {
    return true; // Start time < 0 seconds
  }
  if (subtitle.start >= subtitle.end) {
    return true; // Subtitle start time >= end time
  }
  return false;
}

/// Reorder subtitles by start time and rewrite their indexes to match.
///
/// If [skip] is true, subtitles considered not useful are dropped (empty or
/// whitespace-only content, negative start, or start >= end).
Iterable<Subtitle> sortAndReindex(
  List<Subtitle> subtitles, {
  int startIndex = 1,
  bool inPlace = false,
  bool skip = true,
}) sync* {
  var skipped = 0;
  final sorted = List<Subtitle>.from(subtitles)..sort();
  for (var i = 0; i < sorted.length; i++) {
    final subNum = startIndex + i;
    var subtitle = sorted[i];
    if (!inPlace) {
      subtitle = Subtitle(
        index: subtitle.index,
        start: subtitle.start,
        end: subtitle.end,
        content: subtitle.content,
      );
    }
    if (skip && _shouldSkipSub(subtitle)) {
      skipped++;
      continue;
    }
    subtitle.index = subNum - skipped;
    yield subtitle;
  }
}

/// Convert a list of [Subtitle] objects into a single SRT formatted string.
String compose(
  List<Subtitle> subtitles, {
  bool reindex = true,
  int startIndex = 1,
  String? eol,
  bool inPlace = false,
}) {
  Iterable<Subtitle> subs = subtitles;
  if (reindex) {
    subs = sortAndReindex(
      subtitles,
      startIndex: startIndex,
      inPlace: inPlace,
    );
  }
  return subs.map((s) => s.toSrt(eol: eol)).join();
}
