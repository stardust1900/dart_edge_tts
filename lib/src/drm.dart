/// DRM module: handles the `Sec-MS-GEC` token generation and clock-skew
/// correction used by all API requests to Microsoft Edge's online TTS service.
///
/// Ported from Python `edge_tts/drm.py`.
library;

import 'dart:convert' show utf8;
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;

import 'constants.dart';
import 'exceptions.dart';
import 'util.dart' show makeHttpClient;

/// Seconds between the Windows epoch (1601-01-01) and the Unix epoch (1970-01-01).
const int _winEpochSeconds = 11644473600;

/// 100-nanosecond intervals per second.
const int _hundredNsPerSecond = 10000000;

/// Number of 100-nanosecond ticks in 5 minutes (used to floor the timestamp).
const int _fiveMinutesTicks = 300 * _hundredNsPerSecond;

/// Mutable clock skew in seconds, adjusted when the local clock is off.
double _clockSkewSeconds = 0.0;

/// Adjusts the clock skew in seconds (ac cumulated across retries).
void adjClockSkewSeconds(double skewSeconds) => _clockSkewSeconds += skewSeconds;

/// Returns the current Unix timestamp (seconds) with clock-skew correction.
double getUnixTimestamp() =>
    DateTime.now().toUtc().millisecondsSinceEpoch / 1000.0 + _clockSkewSeconds;

/// Generates a random MUID (32 uppercase hex characters).
String generateMuid() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}

/// Returns a copy of [headers] with the `Cookie: muid=...;` header added.
Map<String, String> headersWithMuid(Map<String, String> headers) {
  final combined = <String, String>{...headers};
  combined['Cookie'] = 'muid=${generateMuid()};';
  return combined;
}

/// Generates the `Sec-MS-GEC` token value.
///
/// The token is derived from the current time in Windows filetime format
/// (adjusted for clock skew and floored to the nearest 5 minutes), hashed with
/// SHA-256 and returned as an uppercased hex digest.
///
/// See: https://github.com/rany2/edge-tts/issues/290#issuecomment-2464956570
String generateSecMsGec() {
  final int nowMs = DateTime.now().toUtc().millisecondsSinceEpoch +
      (_clockSkewSeconds * 1000).round();

  // Windows FILETIME in 100-nanosecond intervals.
  int fileTime = (nowMs + _winEpochSeconds * 1000) * 10000;

  // Round down to the nearest 5 minutes.
  fileTime -= fileTime % _fiveMinutesTicks;

  final strToHash = fileTime.toString() + trustedClientToken;
  final digest = sha256.convert(utf8.encode(strToHash));
  return digest.toString().toUpperCase();
}

final Map<String, int> _monthNums = {
  'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
  'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
};

/// Parses an RFC 2616 date string (e.g. `Wed, 21 Oct 2026 07:28:00 GMT`)
/// into a Unix timestamp. Returns `null` if parsing fails.
double? parseRfc2616Date(String date) {
  try {
    final regex = RegExp(
      r'^[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) '
      r'(\d{2}):(\d{2}):(\d{2}) GMT$',
    );
    final m = regex.firstMatch(date.trim());
    if (m == null) return null;
    final day = int.parse(m.group(1)!);
    final month = _monthNums[m.group(2)!];
    final year = int.parse(m.group(3)!);
    final hour = int.parse(m.group(4)!);
    final minute = int.parse(m.group(5)!);
    final second = int.parse(m.group(6)!);
    if (month == null) return null;
    final dt = DateTime.utc(year, month, day, hour, minute, second);
    return dt.millisecondsSinceEpoch / 1000.0;
  } catch (_) {
    return null;
  }
}

/// Adjusts the clock skew based on the server date in a response header.
void adjustSkewFromDateHeader(String? dateHeader) {
  if (dateHeader == null) {
    throw SkewAdjustmentError('No server date in headers.');
  }
  final serverDate = parseRfc2616Date(dateHeader);
  if (serverDate == null) {
    throw SkewAdjustmentError('Failed to parse server date: $dateHeader');
  }
  final clientDate = getUnixTimestamp();
  adjClockSkewSeconds(serverDate - clientDate);
}

/// Fetches the server date over HTTP and uses it to correct the clock skew.
///
/// This is used as a recovery path when a WebSocket connection fails with a
/// 403 (the voice-list endpoint returns a `date` header even on 403).
Future<void> syncClockFromServer([String? proxy]) async {
  final client = makeHttpClient(proxy);
  try {
    final url = Uri.parse(
      '$voiceListUrl&Sec-MS-GEC=${generateSecMsGec()}'
      '&Sec-MS-GEC-Version=$secMsGecVersion',
    );
    final response = await client.get(url, headers: headersWithMuid(voiceHeaders));
    adjustSkewFromDateHeader(response.headers['date']);
  } finally {
    client.close();
  }
}
