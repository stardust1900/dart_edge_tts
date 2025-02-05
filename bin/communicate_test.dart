import 'package:dart_edge_tts/communicate.dart';

Future<void> main(List<String> args) async {
  try {
    String txt = "锄禾日当午，汗滴禾下土。谁知盘中餐，粒粒皆辛苦。";
    var communicate = Communicate(text: txt);
    // communicate.stream();
    await communicate.save("test.mp3");
  } catch (e, stackTrace) {
    print(e);
    print(stackTrace);
  }

  // test();
}
