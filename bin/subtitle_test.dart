import 'dart:convert';

import 'package:dart_edge_tts/communicate.dart';
import 'package:dart_edge_tts/submaker.dart';
import 'package:dart_edge_tts/typing.dart';

Future<void> main(List<String> args) async {
  try {
    String txt = "锄禾日当午，汗滴禾下土。谁知盘中餐，粒粒皆辛苦。";
    var communicate = Communicate(text: txt);
    var submaker = SubMaker();
    try {
      await for (final message in communicate.stream()) {
        if (message.type == TTSChunkType.audio) {
          if (message.data!.isNotEmpty) {
            //audioSink.add(message.data as Uint8List);
          }
        } else if (message.type == TTSChunkType.wordBoundary) {
          // print(message);
          submaker.feed(message);
          // print("wordBoundary: ${jsonEncode(message.text)}");
        }
      }

      print(submaker.srt);
    } catch (e, stackTrace) {
      print('捕获到异常：$e');
      print('堆栈跟踪：$stackTrace');
    }
  } catch (e, stackTrace) {
    print(e);
    print(stackTrace);
  }
}
