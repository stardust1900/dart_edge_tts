import 'dart:convert';
// import 'dart:io';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'drm.dart';
import 'typing.dart';

Future<List<Voice>?> listVoices() async {
  // final sslContext = SecurityContext.defaultContext;
  // sslContext.setTrustedCertificates(
  //     "${Directory.current.path}/lib/cacert.pem"); // 替换为实际的证书路径

  final client = http.Client();

  try {
    var url = Uri.parse(
        "$voiceListUrl&Sec-MS-GEC=${DRM.generateSecMsGec()}&Sec-MS-GEC-Version=$secMsGecVersion");

    var response = await client.get(
      url,
      headers: DRM.headersWithMuid(voiceHeaders),
      // 如果有代理，可以在这里设置
    );

    if (response.statusCode == 403) {
      DRM.handleClientResponseError(response);
      // 重试时使用全新生成的 token（对应 Python __list_voices 每次重新生成）
      url = Uri.parse(
          "$voiceListUrl&Sec-MS-GEC=${DRM.generateSecMsGec()}&Sec-MS-GEC-Version=$secMsGecVersion");
      response = await client.get(
          url, headers: DRM.headersWithMuid(voiceHeaders));
    }

    if (response.statusCode != 200) {
      throw Exception("Failed to fetch voices: ${response.statusCode}");
    }
    final data = jsonDecode(response.body) as List;
    return data.map((e) => Voice.fromMap(e)).toList();
  } finally {
    client.close();
  }
}

class VoicesManager {
  List<VoicesManagerVoice> _voices = [];
  bool _calledCreate = false;

  // 私有构造函数
  VoicesManager._();

  // 静态异步方法来创建并初始化 VoicesManager
  static Future<VoicesManager> create({List<Voice>? customVoices}) async {
    final manager = VoicesManager._();
    final base = customVoices ?? await listVoices() ?? <Voice>[];
    // 为每个语音补 Language 字段（对应 Python 的 Language = Locale.split("-")[0]）
    manager._voices = base.map((voice) {
      return VoicesManagerVoice(
        name: voice.name,
        shortName: voice.shortName,
        gender: voice.gender,
        locale: voice.locale,
        suggestedCodec: voice.suggestedCodec,
        friendlyName: voice.friendlyName,
        status: voice.status,
        voiceTag: voice.voiceTag,
        language: voice.locale.split("-")[0],
      );
    }).toList();
    manager._calledCreate = true;
    return manager;
  }

  // 查找匹配的语音，对齐 Python 的 kwargs.items() <= voice.items() 子集匹配
  List<VoicesManagerVoice> find({
    String? locale,
    String? language,
    String? gender,
  }) {
    if (!_calledCreate) {
      throw StateError(
          "VoicesManager.find() called before VoicesManager.create()");
    }

    return _voices.where((voice) {
      if (gender != null && voice.gender != gender) {
        return false;
      }
      if (locale != null && voice.locale != locale) {
        return false;
      }
      if (language != null && voice.language != language) {
        return false;
      }
      return true;
    }).toList();
  }

  List<VoicesManagerVoice> get voices => _voices;
}
