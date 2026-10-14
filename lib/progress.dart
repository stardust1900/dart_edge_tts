/// Terminal progress bar for the command line interface.
///
/// Ported from edge-tts' progress.py. This module knows nothing about TTS: it
/// is fed the source text up front, then told which parts of it have been
/// spoken, how far the audio timeline those parts describe reaches, and how
/// many audio bytes have actually arrived.
///
/// Progress is measured in audio, not in text: the service sends its boundary
/// metadata far ahead of the audio it describes, so the text cursor alone is a
/// poor progress indicator. The audio timeline covered by the metadata
/// received so far, divided by the fraction of text that metadata covers,
/// extrapolates to the total length of the audio.
library dart_edge_tts.progress;

import 'dart:io';
import 'dart:math';

import 'package:dart_edge_tts/constants.dart';

const String fullBlock = "█";
// Index i holds the glyph filling i/8 of a cell; index 0 is blank.
const String partialBlocks = " ▏▎▍▌▋▊▉";

// Keep a usable bar even in a very narrow terminal.
const int minBarWidth = 3;
const int defaultWidth = 80;

/// Formats a duration as MM:SS, or H:MM:SS once it reaches an hour.
String formatTime(double seconds) {
  final total = seconds.toInt();
  final minutes = total ~/ 60;
  final secs = total % 60;
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours > 0) {
    return "$hours:${mins.toString().padLeft(2, '0')}:"
        "${secs.toString().padLeft(2, '0')}";
  }
  return "${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
}

/// Formats a byte count as a short human readable string (KB below 1 MB,
/// otherwise MB).
String formatBytes(int numBytes) {
  if (numBytes < 1024 * 1024) {
    return "${numBytes ~/ 1024}KB";
  }
  return "${(numBytes / 1024 / 1024).toStringAsFixed(1)}MB";
}

/// Renders the bar body for the given fill fraction (always exactly [width]
/// characters long).
String renderBar(double fraction, int width) {
  final filled = fraction * width;
  final whole = filled.floor();
  if (whole >= width) {
    return fullBlock * width;
  }
  final partialIndex =
      min(partialBlocks.length - 1, ((filled - whole) * 8).floor());
  final partial = partialBlocks[partialIndex];
  return fullBlock * whole + partial + " " * (width - whole - 1);
}

/// A single line, in place progress bar for a TTS run.
class ProgressBar {
  final String _text;
  final IOSink _stream;
  final int _width;
  final double _minInterval;
  final DateTime Function() _timeFn;

  int _cursor = 0;
  int _audioBytes = 0;
  int _timelineTicks = 0;
  late final DateTime _start;
  DateTime? _lastRender;
  double _fraction = 0.0;
  bool _complete = false;
  bool _finished = false;

  ProgressBar(
    this._text, {
    IOSink? stream,
    int? width,
    double minInterval = 0.1,
    DateTime Function()? timeFn,
  })  : _stream = stream ?? stderr,
        _width = _resolveWidth(width),
        _minInterval = minInterval,
        _timeFn = timeFn ?? DateTime.now {
    _start = _timeFn();
  }

  /// The fraction of the source text spoken so far, between 0 and 1.
  double get textFraction {
    if (_text.isEmpty) {
      return 0.0;
    }
    return min(1.0, _cursor / _text.length);
  }

  /// The fraction of the audio received so far, between 0 and 1.
  ///
  /// Zero until the first boundary event arrives. Never decreases: when the
  /// remaining text turns out to speak for longer than extrapolated, the bar
  /// holds rather than rewinding.
  double get fraction {
    if (_complete) {
      return 1.0;
    }
    final estimatedTotal = _estimatedTotalSeconds();
    if (estimatedTotal > 0) {
      _fraction = max(
        _fraction,
        min(1.0, _receivedSeconds() / estimatedTotal),
      );
    }
    return _fraction;
  }

  double _receivedSeconds() {
    // Seconds of audio received, by exact CBR byte arithmetic.
    return _audioBytes * 8 / mp3BitrateBps;
  }

  double _estimatedTotalSeconds() {
    final tf = textFraction;
    if (tf <= 0 || _timelineTicks <= 0) {
      return 0.0;
    }
    return _timelineTicks / ticksPerSecond / tf;
  }

  /// Moves the cursor past the given piece of spoken text.
  void advance(String spokenText) {
    if (spokenText.isEmpty) {
      return;
    }
    final found = _text.indexOf(spokenText, _cursor);
    if (found >= 0) {
      _cursor = found + spokenText.length;
    }
  }

  /// Records how far into the audio the metadata received so far reaches.
  void setAudioTimeline(int ticks) {
    _timelineTicks = max(_timelineTicks, ticks);
  }

  /// Adds to the count of audio bytes received.
  void addAudioBytes(int numBytes) {
    _audioBytes += numBytes;
  }

  /// Redraws the bar in place, at most once per [_minInterval] seconds.
  void render() {
    final now = _timeFn();
    if (_lastRender != null && now.difference(_lastRender!).inMilliseconds / 1000 < _minInterval) {
      return;
    }
    _lastRender = now;
    _write(_line());
  }

  /// Fills the bar to 100%, ends the line and stops further drawing.
  void finish() {
    if (_finished) {
      return;
    }
    _finished = true;
    _complete = true;
    _write(_line(), end: "\n");
  }

  /// Ends the line without claiming the run completed (used when abandoned).
  void close() {
    if (_finished) {
      return;
    }
    _finished = true;
    if (_lastRender != null) {
      _stream.write("\n");
      _stream.flush();
    }
  }

  String _line() {
    final f = fraction;
    final elapsed = _timeFn().difference(_start).inMilliseconds / 1000;
    final eta = f > 0 ? formatTime(elapsed / f - elapsed) : "--:--";
    final prefix = "${(f * 100).toInt().toString().padLeft(3, ' ')}%|";
    final suffix = "| ${formatBytes(_audioBytes)}  ${formatTime(elapsed)}<$eta";
    final barWidth = max(minBarWidth, _width - prefix.length - suffix.length);
    return '$prefix${renderBar(f, barWidth)}$suffix';
  }

  void _write(String line, {String end = ""}) {
    _stream.write("\r${line.padRight(_width)}$end");
    _stream.flush();
  }

  static int _resolveWidth(int? width) {
    if (width != null) {
      return width;
    }
    int cols;
    try {
      cols = stdout.terminalColumns;
    } catch (_) {
      cols = defaultWidth;
    }
    return cols - 1;
  }
}
