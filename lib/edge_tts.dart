/// edge_tts: use Microsoft Edge's online text-to-speech service from Dart.
///
/// A faithful port of the Python [`edge-tts`](https://github.com/rany2/edge-tts)
/// package.
///
/// Basic usage:
///
/// ```dart
/// import 'package:edge_tts/edge_tts.dart';
///
/// void main() async {
///   final communicate = Communicate('Hello, world!', 'en-US-EmmaMultilingualNeural');
///   await communicate.save('hello.mp3');
/// }
/// ```
library edge_tts;

export 'src/constants.dart';
export 'src/exceptions.dart';
export 'src/drm.dart'
    show generateSecMsGec, generateMuid, headersWithMuid, syncClockFromServer;
export 'src/communicate.dart' show Communicate, TtsConfig, TtsChunk;
export 'src/voices.dart' show listVoices, VoicesManager, Voice;
export 'src/submaker.dart' show SubMaker;
export 'src/srt_composer.dart' show Subtitle, compose, composeVtt;
