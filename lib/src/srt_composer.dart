/// A tiny library for composing SRT (and WebVTT) subtitle files.
///
/// Based on https://github.com/cdown/srt (MIT), trimmed to the subset needed by
/// edge_tts and ported to Dart.
library;

/// The metadata relating to a single subtitle cue.
class Subtitle {
  /// The SRT/VTT index for this subtitle (0 = auto-index on write).
  final int? index;

  /// When the subtitle should start being shown.
  final Duration start;

  /// When the subtitle should stop being shown.
  final Duration end;

  /// The subtitle content (may contain `\n` for line breaks).
  final String content;

  /// Creates a [Subtitle].
  const Subtitle({
    this.index,
    required this.start,
    required this.end,
    required this.content,
  });

  /// Converts this subtitle to an SRT block.
  String toSrt({String? eol}) {
    final outputContent = makeLegalContent(content);
    final e = eol ?? '\n';
    final contentOut =
        (eol != null && eol != '\n') ? outputContent.replaceAll('\n', eol) : outputContent;
    return '${index ?? 0}$e${timestamp(start)} --> ${timestamp(end)}$e'
        '$contentOut$e$e';
  }

  /// Converts this subtitle to a WebVTT cue.
  String toVtt() {
    final outputContent = makeLegalContent(content);
    return '${index ?? 0}\n${timestampVtt(start)} --> ${timestampVtt(end)}\n'
        '$outputContent\n\n';
  }

  @override
  String toString() => toSrt();
}

/// Removes illegal content from a content block (blank lines, leading/trailing
/// blank lines).
String makeLegalContent(String content) {
  if (content.isNotEmpty && content[0] != '\n' && !content.contains('\n\n')) {
    return content;
  }
  return content.trim().replaceAll(RegExp(r'\n\n+'), '\n');
}

String _p2(int n) => n.toString().padLeft(2, '0');
String _p3(int n) => n.toString().padLeft(3, '0');

/// Converts a [Duration] to an SRT timestamp (`HH:MM:SS,mmm`).
String timestamp(Duration d) {
  final hrs = d.inHours;
  final mins = d.inMinutes.remainder(60);
  final secs = d.inSeconds.remainder(60);
  final ms = d.inMilliseconds.remainder(1000);
  return '${_p2(hrs)}:${_p2(mins)}:${_p2(secs)},${_p3(ms)}';
}

/// Converts a [Duration] to a WebVTT timestamp (`HH:MM:SS.mmm`).
String timestampVtt(Duration d) => timestamp(d).replaceFirst(',', '.');

List<Subtitle> _reindex(List<Subtitle> subtitles, int startIndex) {
  final sorted = [...subtitles]
    ..sort((a, b) {
      final c = a.start.compareTo(b.start);
      if (c != 0) return c;
      final c2 = a.end.compareTo(b.end);
      if (c2 != 0) return c2;
      return (a.index ?? 0).compareTo(b.index ?? 0);
    });
  return [
    for (var i = 0; i < sorted.length; i++)
      Subtitle(
        index: startIndex + i,
        start: sorted[i].start,
        end: sorted[i].end,
        content: sorted[i].content,
      )
  ];
}

/// Converts a list of [Subtitle] objects to a joined SRT string.
String compose(
  List<Subtitle> subtitles, {
  bool reindex = true,
  int startIndex = 1,
}) {
  final subs = reindex ? _reindex(subtitles, startIndex) : subtitles;
  return subs.map((s) => s.toSrt()).join();
}

/// Converts a list of [Subtitle] objects to a joined WebVTT string.
String composeVtt(
  List<Subtitle> subtitles, {
  bool reindex = true,
  int startIndex = 1,
}) {
  final subs = reindex ? _reindex(subtitles, startIndex) : subtitles;
  return 'WEBVTT\n\n${subs.map((s) => s.toVtt()).join()}';
}
