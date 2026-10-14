/// Functions and classes to list available voices and to find voices by
/// attribute.
///
/// Ported from Python `edge_tts/voices.py`.
library;

import 'dart:convert' show jsonDecode;

import 'package:http/http.dart' as http;

import 'constants.dart';
import 'drm.dart';
import 'util.dart' show makeHttpClient;

/// A voice description as returned by the voice-list endpoint.
typedef Voice = Map<String, dynamic>;

List<Voice> _parseVoices(String body) {
  final data = (jsonDecode(body) as List).cast<Map<String, dynamic>>();
  for (final voice in data) {
    voice.putIfAbsent('VoiceTag', () => <String, dynamic>{});
    final tag = voice['VoiceTag'] as Map<String, dynamic>;
    tag.putIfAbsent('ContentCategories', () => <dynamic>[]);
    tag.putIfAbsent('VoicePersonalities', () => <dynamic>[]);
  }
  return data;
}

/// Lists all available voices and their attributes.
Future<List<Voice>> listVoices({
  http.Client? client,
  String? proxy,
}) async {
  final ownClient = client ?? makeHttpClient(proxy);
  try {
    final url = Uri.parse(
      '$voiceListUrl&Sec-MS-GEC=${generateSecMsGec()}'
      '&Sec-MS-GEC-Version=$secMsGecVersion',
    );
    final response = await ownClient.get(
      url,
      headers: headersWithMuid(voiceHeaders),
    );
    if (response.statusCode == 403) {
      adjustSkewFromDateHeader(response.headers['date']);
      final retry = await ownClient.get(
        url,
        headers: headersWithMuid(voiceHeaders),
      );
      return _parseVoices(retry.body);
    }
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to list voices: HTTP ${response.statusCode}',
      );
    }
    return _parseVoices(response.body);
  } finally {
    if (client == null) ownClient.close();
  }
}

/// A class to find the correct voice based on its attributes.
class VoicesManager {
  /// The populated list of voices (each includes a derived `Language` field).
  List<Map<String, dynamic>> voices = [];

  bool _calledCreate = false;

  /// Creates a [VoicesManager] and populates it with all available voices.
  /// Pass [customVoices] to use a fixed list instead of fetching from the
  /// service.
  static Future<VoicesManager> create({List<Voice>? customVoices}) async {
    final self = VoicesManager();
    final list = customVoices ?? await listVoices();
    self.voices = [
      for (final v in list)
        {
          ...v,
          'Language': (v['Locale'] as String).split('-').first,
        }
    ];
    self._calledCreate = true;
    return self;
  }

  /// Finds all matching voices based on the provided attributes.
  ///
  /// Example: `manager.find(gender: 'Male', language: 'es')` or
  /// `manager.find(locale: 'es-AR')`.
  List<Map<String, dynamic>> find({
    String? gender,
    String? locale,
    String? language,
  }) {
    if (!_calledCreate) {
      throw StateError('VoicesManager.find() called before VoicesManager.create()');
    }
    final criteria = <String, String>{};
    if (gender != null) criteria['Gender'] = gender;
    if (locale != null) criteria['Locale'] = locale;
    if (language != null) criteria['Language'] = language;
    return voices
        .where((voice) =>
            criteria.entries.every((e) => voice[e.key] == e.value))
        .toList();
  }
}
