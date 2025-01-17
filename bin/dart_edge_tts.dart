import 'dart:convert';
import 'dart:io';

import 'package:dart_edge_tts/dart_edge_tts.dart' as dart_edge_tts;
import 'package:dart_edge_tts/typing.dart';
import 'package:dart_edge_tts/voices.dart';

Future<void> main(List<String> arguments) async {
  // print('Hello world: ${dart_edge_tts.calculate()}!');
  // VoicesManager manager = await VoicesManager.create();
  // print(manager.voices.map((v) {
  //   print(v.toMap());
  // }));

  String data =
      File("${Directory.current.path}/bin/voices.json").readAsStringSync();
  // print(data);
  final json = jsonDecode(data);
  final voices = json.map((e) => Voice.fromMap(e)).toList();
  print(voices.length);
  voices.forEach((v) {
    // print(v.locale);
    if (v.locale.startsWith('zh')) {
      print("${v.shortName}:${v.friendlyName}");
    }
  });
}
// zh-HK-HiuGaaiNeural:Microsoft HiuGaai Online (Natural) - Chinese (Cantonese Traditional)
// zh-HK-HiuMaanNeural:Microsoft HiuMaan Online (Natural) - Chinese (Hong Kong)
// zh-HK-WanLungNeural:Microsoft WanLung Online (Natural) - Chinese (Hong Kong)
// zh-CN-XiaoxiaoNeural:Microsoft Xiaoxiao Online (Natural) - Chinese (Mainland)
// zh-CN-XiaoyiNeural:Microsoft Xiaoyi Online (Natural) - Chinese (Mainland)
// zh-CN-YunjianNeural:Microsoft Yunjian Online (Natural) - Chinese (Mainland)
// zh-CN-YunxiNeural:Microsoft Yunxi Online (Natural) - Chinese (Mainland)
// zh-CN-YunxiaNeural:Microsoft Yunxia Online (Natural) - Chinese (Mainland)
// zh-CN-YunyangNeural:Microsoft Yunyang Online (Natural) - Chinese (Mainland)
// zh-CN-liaoning-XiaobeiNeural:Microsoft Xiaobei Online (Natural) - Chinese (Northeastern Mandarin)
// zh-TW-HsiaoChenNeural:Microsoft HsiaoChen Online (Natural) - Chinese (Taiwan)
// zh-TW-YunJheNeural:Microsoft YunJhe Online (Natural) - Chinese (Taiwan)
// zh-TW-HsiaoYuNeural:Microsoft HsiaoYu Online (Natural) - Chinese (Taiwanese Mandarin)
// zh-CN-shaanxi-XiaoniNeural:Microsoft Xiaoni Online (Natural) - Chinese (Zhongyuan Mandarin Shaanxi)
