import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'constants.dart';
import 'exceptions.dart';

/// DRM module is used to handle DRM operations with clock skew correction.
/// Currently the only DRM operation is generating the Sec-MS-GEC token value
/// used in all API requests to Microsoft Edge's online text-to-speech service.

const int _winEpoch = 11644473600;
const double _sToNs = 1e9;
const int _u32Mask = 0xFFFFFFFF;

// FIPS 180-4: https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf
const List<int> _sha256Initial = [
  0x6A09E667,
  0xBB67AE85,
  0x3C6EF372,
  0xA54FF53A,
  0x510E527F,
  0x9B05688C,
  0x1F83D9AB,
  0x5BE0CD19,
];

const List<int> _sha256State = [
  0xFD9FBEA2,
  0x91243CE7,
  0xBE499094,
  0xCD2E1E0A,
  0x6C006F49,
  0x04BD35AB,
  0xFEB0A7E4,
  0x03EFFBD2,
];

const List<int> _sha256Schedule = [
  0xEB24BF9E,
  0x1558691F,
  0xA0C09EE2,
  0x0CFA32BA,
  0xA622EE8C,
  0xD1DD9491,
  0xC0DD25A0,
  0xF9E70AB6,
  0xF0C31573,
  0x7058CE4E,
  0x7188E606,
  0x00E5AB33,
  0xD258B060,
  0x72766564,
];

const List<int> _sha256RoundConstants = [
  0x428A2F98,
  0x71374491,
  0xB5C0FBCF,
  0xE9B5DBA5,
  0x3956C25B,
  0x59F111F1,
  0x923F82A4,
  0xAB1C5ED5,
  0xD807AA98,
  0x12835B01,
  0x243185BE,
  0x550C7DC3,
  0x72BE5D74,
  0x80DEB1FE,
  0x9BDC06A7,
  0xC19BF174,
  0xE49B69C1,
  0xEFBE4786,
  0x0FC19DC6,
  0x240CA1CC,
  0x2DE92C6F,
  0x4A7484AA,
  0x5CB0A9DC,
  0x76F988DA,
  0x983E5152,
  0xA831C66D,
  0xB00327C8,
  0xBF597FC7,
  0xC6E00BF3,
  0xD5A79147,
  0x06CA6351,
  0x14292967,
  0x27B70A85,
  0x2E1B2138,
  0x4D2C6DFC,
  0x53380D13,
  0x650A7354,
  0x766A0ABB,
  0x81C2C92E,
  0x92722C85,
  0xA2BFE8A1,
  0xA81A664B,
  0xC24B8B70,
  0xC76C51A3,
  0xD192E819,
  0xD6990624,
  0xF40E3585,
  0x106AA070,
  0x19A4C116,
  0x1E376C08,
  0x2748774C,
  0x34B0BCB5,
  0x391C0CB3,
  0x4ED8AA4A,
  0x5B9CCA4F,
  0x682E6FF3,
  0x748F82EE,
  0x78A5636F,
  0x84C87814,
  0x8CC70208,
  0x90BEFFFA,
  0xA4506CEB,
  0xBEF9A3F7,
  0xC67178F2,
];

const int _sha256Adjustment = 0xC9DC06A7;

final List<int> _sha256BlockConstants = [
  ..._sha256RoundConstants.sublist(0, 14),
  _sha256Adjustment,
  ..._sha256RoundConstants.sublist(15),
];

const int _sha256Sigma0Adjustment = 0x059C0B80;
const int _sha256Sigma1Adjustment = 0x000B92C0;

const List<List<int>> _cs64Coefficients = [
  [0xE82E91B1, 0xB32700D0],
  [0x44DE24C6, 0x88DFF51D],
  [0x3BEB65BC, 0x29514038],
  [0xC89C5933, 0xB328CBDF],
  [0x8D1EC211, 0xD405B4D5],
  [0x314EF5D5, 0x26E55F3C],
  [0xE92491B1, 0x607801C6],
  [0xF0A5B9D5, 0x82B2C1FB],
  [0x06064CF3, 0xFA51A3DA],
  [0xDA79FA60, 0x207CC464],
  [0xBED20560, 0x3C3C74F3],
  [0x89F9C9F8, 0xD2D14B61],
  [0x35FA38C6, 0xBB04A2C1],
  [0xCB49E3C6, 0xC5626167],
];

const int _cs64Factor = 0x82893933;
const int _cs64Adjustment0 = 0xF2F90B1A;
const int _cs64Adjustment1 = 0x0B1A0000;

int _rotr(int value, int n) {
  value &= _u32Mask;
  return (((value >> n) | ((value << (32 - n)) & _u32Mask))) & _u32Mask;
}

int _rol16(int value) {
  value &= _u32Mask;
  return ((value << 16) | (value >> 16)) & _u32Mask;
}

int _lowerSigma0(int value) {
  return ((value >> 7) ^ (value << 25) ^ (value >> 18) ^ (value << 14) ^ (value >> 3)) &
      _u32Mask;
}

int _lowerSigma1(int value) {
  return ((value >> 17) ^
          (value << 15) ^
          (value >> 19) ^
          (value << 13) ^
          (value >> 10)) &
      _u32Mask;
}

int _upperSigma0(int value) {
  return _rotr(value, 2) ^ _rotr(value, 13) ^ _rotr(value, 22);
}

int _upperSigma1(int value) {
  return _rotr(value, 6) ^ _rotr(value, 11) ^ _rotr(value, 25);
}

List<int> _wordsLe4Even(Uint8List data) {
  final int pad = ((-data.length) % 4);
  final padded = Uint8List(data.length + pad);
  padded.setAll(0, data);
  if (padded.isEmpty) {
    return [];
  }
  final bd = ByteData.sublistView(padded);
  final n = padded.length ~/ 4;
  final words = <int>[];
  for (int i = 0; i < n; i++) {
    words.add(bd.getUint32(i * 4, Endian.little) & _u32Mask);
  }
  if (words.length % 2 == 1) {
    words.add(0);
  }
  return words;
}

int _beBytes(Uint8List data, int start, int len) {
  int v = 0;
  for (int i = 0; i < len; i++) {
    v = (v << 8) | (data[start + i] & 0xFF);
  }
  return v & _u32Mask;
}

List<int> _sha256Rounds(List<int> state, List<int> words, [int firstRound = 0]) {
  int a = state[0],
      b = state[1],
      c = state[2],
      d = state[3],
      e = state[4],
      f = state[5],
      g = state[6],
      h = state[7];
  final constants =
      (firstRound == 14) ? _sha256BlockConstants : _sha256RoundConstants;
  final aligned = min(64, ((firstRound + 7) ~/ 8) * 8);
  for (int index = firstRound; index < aligned; index++) {
    final t1 = (h +
            _upperSigma1(e) +
            (g ^ (e & (f ^ g))) +
            constants[index] +
            words[index]) &
        _u32Mask;
    final t2 = (_upperSigma0(a) + ((a & b) | (c & (a | b)))) & _u32Mask;
    h = g;
    g = f;
    f = e;
    e = (d + t1) & _u32Mask;
    d = c;
    c = b;
    b = a;
    a = (t1 + t2) & _u32Mask;
  }
  for (int index = aligned; index < 64; index += 8) {
    int t;
    t = (h +
            _upperSigma1(e) +
            (g ^ (e & (f ^ g))) +
            constants[index] +
            words[index]) &
        _u32Mask;
    d = (d + t) & _u32Mask;
    h = (t + _upperSigma0(a) + ((a & b) | (c & (a | b)))) & _u32Mask;

    t = (g +
            _upperSigma1(d) +
            (f ^ (d & (e ^ f))) +
            constants[index + 1] +
            words[index + 1]) &
        _u32Mask;
    c = (c + t) & _u32Mask;
    g = (t + _upperSigma0(h) + ((h & a) | (b & (h | a)))) & _u32Mask;

    t = (f +
            _upperSigma1(c) +
            (e ^ (c & (d ^ e))) +
            constants[index + 2] +
            words[index + 2]) &
        _u32Mask;
    b = (b + t) & _u32Mask;
    f = (t + _upperSigma0(g) + ((g & h) | (a & (g | h)))) & _u32Mask;

    t = (e +
            _upperSigma1(b) +
            (d ^ (b & (c ^ d))) +
            constants[index + 3] +
            words[index + 3]) &
        _u32Mask;
    a = (a + t) & _u32Mask;
    e = (t + _upperSigma0(f) + ((f & g) | (h & (f | g)))) & _u32Mask;

    t = (d +
            _upperSigma1(a) +
            (c ^ (a & (b ^ c))) +
            constants[index + 4] +
            words[index + 4]) &
        _u32Mask;
    h = (h + t) & _u32Mask;
    d = (t + _upperSigma0(e) + ((e & f) | (g & (e | f)))) & _u32Mask;

    t = (c +
            _upperSigma1(h) +
            (b ^ (h & (a ^ b))) +
            constants[index + 5] +
            words[index + 5]) &
        _u32Mask;
    g = (g + t) & _u32Mask;
    c = (t + _upperSigma0(d) + ((d & e) | (f & (d | e)))) & _u32Mask;

    t = (b +
            _upperSigma1(g) +
            (a ^ (g & (h ^ a))) +
            constants[index + 6] +
            words[index + 6]) &
        _u32Mask;
    f = (f + t) & _u32Mask;
    b = (t + _upperSigma0(c) + ((c & d) | (e & (c | d)))) & _u32Mask;

    t = (a +
            _upperSigma1(f) +
            (h ^ (f & (g ^ h))) +
            constants[index + 7] +
            words[index + 7]) &
        _u32Mask;
    e = (e + t) & _u32Mask;
    a = (t + _upperSigma0(b) + ((b & c) | (d & (b | c)))) & _u32Mask;
  }
  return [a, b, c, d, e, f, g, h];
}

void _expandSha256Schedule(List<int> words, [int firstWord = 16]) {
  final mask = _u32Mask;
  for (int index = firstWord; index < 64; index++) {
    final x = words[index - 2];
    final y = words[index - 15];
    final sigma1 =
        (x >> 17) ^ (x << 15) ^ (x >> 19) ^ (x << 13) ^ (x >> 10);
    final sigma0 =
        (y >> 7) ^ (y << 25) ^ (y >> 18) ^ (y << 14) ^ (y >> 3);
    words.add((sigma1 + words[index - 7] + sigma0 + words[index - 16]) & mask);
  }
}

List<int> _sha256Init(Uint8List data) {
  final mask = _u32Mask;
  final words = List<int>.filled(14, 0, growable: true);
  words.add(_beBytes(data, 0, 3));
  words.add(_beBytes(data, 3, 4));
  for (int index = 16; index < 30; index++) {
    int value = _sha256Schedule[index - 16];
    if (index - 2 >= 14) {
      value += (index == 16)
          ? (_lowerSigma1(words[index - 2]) ^ _sha256Sigma1Adjustment)
          : _lowerSigma1(words[index - 2]);
    }
    if (index - 7 >= 14) {
      value += words[index - 7];
    }
    if (index - 15 >= 14) {
      value += (index == 29)
          ? (_lowerSigma0(words[index - 15]) ^ _sha256Sigma0Adjustment)
          : _lowerSigma0(words[index - 15]);
    }
    words.add(value & mask);
  }
  words.add((_lowerSigma1(words[28]) +
          words[23] +
          _lowerSigma0(words[15]) +
          words[14] +
          _sha256Adjustment -
          _sha256RoundConstants[14]) &
      mask);
  _expandSha256Schedule(words, 31);
  final working = _sha256Rounds(_sha256State, words, 14);
  return [for (int i = 0; i < 8; i++) (_sha256Initial[i] + working[i]) & mask];
}

Uint8List _sha256Digest(Uint8List data) {
  if (data.length < 7) {
    throw ArgumentError("Token salt must contain at least seven bytes");
  }
  final mask = _u32Mask;
  final length = 57 + data.length;
  final zerosCount = ((55 - length) % 64);
  final body = data.sublist(7);
  final padded = BytesBuilder();
  padded.add(body);
  padded.addByte(0x80);
  for (int i = 0; i < zerosCount; i++) {
    padded.addByte(0x00);
  }
  final lenBd = ByteData(8);
  lenBd.setUint64(0, length * 8, Endian.big);
  padded.add(lenBd.buffer.asUint8List());
  final paddedBytes = padded.toBytes();

  var curState = _sha256Init(data.sublist(0, 7));
  for (int offset = 0; offset < paddedBytes.length; offset += 64) {
    final block = paddedBytes.sublist(offset, offset + 64);
    final blockBd = ByteData.sublistView(block);
    final words = <int>[
      for (int i = 0; i < 16; i++) blockBd.getUint32(i * 4, Endian.big) & mask
    ];
    _expandSha256Schedule(words);
    final working = _sha256Rounds(curState, words);
    curState = [for (int i = 0; i < 8; i++) (curState[i] + working[i]) & mask];
  }
  final out = ByteData(32);
  for (int i = 0; i < 8; i++) {
    out.setUint32(i * 4, curState[i], Endian.big);
  }
  return out.buffer.asUint8List();
}

List<int> _cs64Digest(Uint8List data, Uint8List digest) {
  final mask = _u32Mask;
  final bd = ByteData.sublistView(digest);
  int keyA = bd.getUint32(0, Endian.little) | 1;
  int keyB = bd.getUint32(4, Endian.little) | 1;
  final factors = [
    (keyA * _cs64Factor) & mask,
    (keyB * _cs64Factor) & mask,
  ];
  final terms = <int>[
    for (int index = 0; index < _cs64Coefficients.length; index++)
      (_cs64Coefficients[index][0] * factors[index % 2]) & mask
  ];
  final offsets = [for (final c in _cs64Coefficients) c[1]];

  final prefixed = Uint8List(data.length + 1);
  prefixed[0] = 0x00;
  prefixed.setAll(1, data);
  final dataWords = _wordsLe4Even(prefixed);
  for (int index = 0; index < dataWords.length; index++) {
    final word = dataWords[index];
    int term = (word * (index % 2 == 0 ? keyA : keyB)) & mask;
    int offset =
        (_rol16(word) * (index % 2 == 0 ? 0xEF0569FB : 0xC31713DB)) & mask;
    if (index == 0) {
      term += _cs64Adjustment0 * factors[0];
      offset += _cs64Adjustment1;
    }
    terms.add(term & mask);
    offsets.add(offset & mask);
  }

  int swapAcc = 0;
  int swapLast = 0;
  int state = 0;
  int acc = 0;
  for (int index = 0; index < terms.length; index += 2) {
    final x = terms[index];
    final y = terms[index + 1];
    var t = _rol16((offsets[index] + x) & mask);
    var q = (t * 0x76F50F34) & mask;
    swapAcc += ((_rol16(q) * 0xC3EFEA97 + q) & mask);
    t = _rol16((offsets[index + 1] + y) & mask);
    q = (t * 0x1881CE3C) & mask;
    swapLast = (_rol16(q) * 0x35BD1EC9 + q) & mask;
    swapAcc = (swapAcc + swapLast) & mask;

    state = (state * keyA + x) & mask;
    state = (_rol16(state) * 0xCF98B111) & mask;
    state = (_rol16(state) * 0x87085B9F) & mask;
    state = (_rol16(state) * 0x12CEB96D) & mask;
    state = (_rol16(state) * 0x257E1D83) & mask;
    acc += state;
    t = (state * keyB + y) & mask;
    t = (_rol16(t) * 0xA27416F5) & mask;
    t = (_rol16(t) * 0xD38396FF) & mask;
    state = (_rol16((_rol16(t) * 0x7C932B89) & mask) * 0xBFA49F69) & mask;
    acc = (acc + state) & mask;
  }
  return [swapLast ^ state, swapAcc ^ acc];
}

List<String> _tokenHash(Uint8List data) {
  final digest = _sha256Digest(data);
  final cs = _cs64Digest(data, digest);
  final csBd = ByteData(8);
  csBd.setUint32(0, cs[0], Endian.little);
  csBd.setUint32(4, cs[1], Endian.little);
  final csHex = csBd.buffer
      .asUint8List()
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
  final shaHex = digest
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
  return [csHex, shaHex];
}

String generateSecMsGecV2([double? unixTimestamp]) {
  double ticks;
  if (unixTimestamp == null) {
    ticks = DRM.getUnixTimestamp();
  } else {
    ticks = unixTimestamp;
  }
  ticks += _winEpoch;
  ticks -= ticks % 300;
  ticks *= _sToNs / 100;
  final strToHash =
      utf8.encode("${ticks.toInt()}$trustedClientToken").sublist(0);
  final csSha = _tokenHash(strToHash);
  return "${csSha[0]}-${csSha[1]}";
}

class DRM {
  /// Class to handle DRM operations with clock skew correction.
  static double clockSkewSeconds = 0.0;

  /// Adjust the clock skew in seconds in case the system clock is off.
  static void adjClockSkewSeconds(double skewSeconds) {
    DRM.clockSkewSeconds += skewSeconds;
  }

  /// Gets the current timestamp in Unix format with clock skew correction.
  static double getUnixTimestamp() {
    return DateTime.now().toUtc().microsecondsSinceEpoch / 1000000 +
        DRM.clockSkewSeconds;
  }

  /// Parses an RFC 2616 date string into a Unix timestamp.
  static double? parseRfc2616Date(String date) {
    try {
      return HttpDate.parse(date).toUtc().millisecondsSinceEpoch / 1000;
    } catch (_) {
      return null;
    }
  }

  /// Handle a client response error, adjusting clock skew based on server date.
  static void handleClientResponseError(http.Response response) {
    if (!response.headers.containsKey('date')) {
      throw SkewAdjustmentError("No server date in headers.");
    }
    final serverDate = response.headers['date'];
    if (serverDate == null) {
      throw SkewAdjustmentError("No server date in headers.");
    }
    final serverDateParsed = DRM.parseRfc2616Date(serverDate);
    if (serverDateParsed == null) {
      throw SkewAdjustmentError("Failed to parse server date: $serverDate");
    }
    final clientDate = DRM.getUnixTimestamp();
    DRM.adjClockSkewSeconds(serverDateParsed - clientDate);
  }

  /// Generates the Sec-MS-GEC token value (v2 format).
  static String generateSecMsGec() {
    return generateSecMsGecV2();
  }

  /// Generates a random MUID.
  static String generateMuid() {
    final rnd = Random.secure();
    final buf = StringBuffer();
    for (int i = 0; i < 32; i++) {
      buf.write(rnd.nextInt(16).toRadixString(16));
    }
    return buf.toString().toUpperCase();
  }

  /// Returns a copy of the given headers with the MUID header added.
  static Map<String, String> headersWithMuid(Map<String, String> headers) {
    final combinedHeaders = Map<String, String>.from(headers);
    assert(!combinedHeaders.containsKey("Cookie"));
    combinedHeaders["Cookie"] = "muid=${DRM.generateMuid()};";
    return combinedHeaders;
  }
}

void main(List<String> args) {
  DRM.generateSecMsGec();
}
