/// Utility functions for edge_tts: XML escaping, text cleaning, text splitting,
/// SSML/date string helpers, HTTP header parsing and a proxy-aware HTTP client.
///
/// Ported from Python `edge_tts/util.py` (the CLI module) and
/// `edge_tts/communicate.py` helpers.
library;

import 'dart:convert' show utf8;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Escapes the five XML special characters.
String xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Unescapes the five XML special characters (mirrors `xml.sax.saxutils.unescape`).
String xmlUnescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// The service does not support a couple of character ranges (most importantly
/// the vertical tab, common in OCR-ed PDFs). Replacing them with a space avoids
/// a server-side error.
String removeIncompatibleCharacters(String s) {
  final buffer = StringBuffer();
  for (final rune in s.runes) {
    final code = rune;
    if ((code <= 8) || (code >= 11 && code <= 12) || (code >= 14 && code <= 31)) {
      buffer.write(' ');
    } else {
      buffer.writeCharCode(code);
    }
  }
  return buffer.toString();
}

/// Returns a JavaScript-style date string (e.g.
/// `Wed Oct 21 2026 07:28:00 GMT+0000 (Coordinated Universal Time)`).
String dateToString() {
  final now = DateTime.now().toUtc();
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final wd = days[now.weekday - 1];
  final mo = months[now.month - 1];
  final dd = now.day.toString().padLeft(2, '0');
  final yyyy = now.year.toString();
  final hh = now.hour.toString().padLeft(2, '0');
  final mm = now.minute.toString().padLeft(2, '0');
  final ss = now.second.toString().padLeft(2, '0');
  return '$wd $mo $dd $yyyy $hh:$mm:$ss GMT+0000 (Coordinated Universal Time)';
}

/// Builds the `X-RequestId`/`Content-Type`/`X-Timestamp`/`Path` header block
/// followed by the SSML body (mirrors `ssml_headers_plus_data`).
String ssmlHeadersPlusData(String requestId, String timestamp, String ssml) {
  // NOTE: the trailing `Z` after the timestamp is intentional (Microsoft Edge bug).
  return 'X-RequestId:$requestId\r\n'
      'Content-Type:application/ssml+xml\r\n'
      'X-Timestamp:${timestamp}Z\r\n'
      'Path:ssml\r\n\r\n'
      '$ssml';
}

/// Builds the SSML document for a single request.
String mkssml(
  String voice,
  String pitch,
  String rate,
  String volume,
  String escapedText,
) {
  return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' "
      "xml:lang='en-US'>"
      "<voice name='$voice'>"
      "<prosody pitch='$pitch' rate='$rate' volume='$volume'>"
      "$escapedText"
      "</prosody>"
      "</voice>"
      "</speak>";
}

/// Parses an HTTP-like `Key: Value\r\n` header block into a map.
Map<String, String> parseHttpLikeHeaders(String raw) {
  final headers = <String, String>{};
  for (final line in raw.split('\r\n')) {
    if (line.isEmpty) continue;
    final idx = line.indexOf(':');
    if (idx < 0) continue;
    final key = line.substring(0, idx).trim();
    final value = line.substring(idx + 1).trim();
    headers[key] = value;
  }
  return headers;
}

int _findLastNewlineOrSpaceWithinLimit(List<int> text, int limit) {
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

int _findSafeUtf8SplitPoint(List<int> text) {
  int splitAt = text.length;
  while (splitAt > 0) {
    try {
      utf8.decode(text.sublist(0, splitAt));
      return splitAt;
    } on FormatException {
      splitAt--;
    }
  }
  return splitAt;
}

int _lastIndexOfByte(List<int> text, int byte, int end) {
  for (int i = end - 1; i >= 0; i--) {
    if (text[i] == byte) return i;
  }
  return -1;
}

int _indexOfByteFrom(List<int> text, int byte, int start, int end) {
  for (int i = start; i < end; i++) {
    if (text[i] == byte) return i;
  }
  return -1;
}

int _adjustSplitPointForXmlEntity(List<int> text, int splitAt) {
  int s = splitAt;
  while (s > 0) {
    final amp = _lastIndexOfByte(text, 0x26 /* & */, s);
    if (amp < 0) break;
    final semi = _indexOfByteFrom(text, 0x3B /* ; */, amp, s);
    if (semi != -1) break; // terminated entity, safe to split here
    s = amp;
  }
  return s;
}

/// Splits [text] into chunks, each not exceeding [byteLength] bytes, preferring
/// natural boundaries (newlines, spaces) while never splitting a multi-byte
/// UTF-8 character or an XML entity in half.
Iterable<String> splitTextByByteLength(String text, int byteLength) sync* {
  if (byteLength <= 0) {
    throw ArgumentError('byte_length must be greater than 0');
  }
  List<int> bytes = utf8.encode(text);
  while (bytes.length > byteLength) {
    int splitAt = _findLastNewlineOrSpaceWithinLimit(bytes, byteLength);
    if (splitAt < 0) splitAt = _findSafeUtf8SplitPoint(bytes);
    splitAt = _adjustSplitPointForXmlEntity(bytes, splitAt);
    if (splitAt < 0) {
      throw ArgumentError(
        'Maximum byte length is too small or invalid text structure.',
      );
    }
    final chunk = utf8.decode(bytes.sublist(0, splitAt)).trim();
    if (chunk.isNotEmpty) yield chunk;
    bytes = bytes.sublist(splitAt > 0 ? splitAt : 1);
  }
  final remaining = utf8.decode(bytes).trim();
  if (remaining.isNotEmpty) yield remaining;
}

/// Returns a proxy-aware [http.Client].
///
/// When [proxy] is `null`, the default client is returned. Otherwise an
/// [http.IOClient] backed by an [HttpClient] configured to route through the
/// proxy is used.
http.Client makeHttpClient([String? proxy]) {
  if (proxy == null) return http.Client();
  var hostPort = proxy;
  final schemeMatch = RegExp(r'^https?://([^/]+)').firstMatch(proxy);
  if (schemeMatch != null) hostPort = schemeMatch.group(1)!;
  final httpClient = HttpClient();
  httpClient.findProxy = (Uri uri) => 'PROXY $hostPort;';
  return IOClient(httpClient);
}
