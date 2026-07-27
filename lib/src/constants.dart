/// Constants for the edge_tts package.
///
/// Ported from Python `edge_tts/constants.py`.
library;

const String baseUrl =
    "speech.platform.bing.com/consumer/speech/synthesize/readaloud";
const String trustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4";

const String wssUrl =
    "wss://$baseUrl/edge/v1?TrustedClientToken=$trustedClientToken";
const String voiceListUrl =
    "https://$baseUrl/voices/list?trustedclienttoken=$trustedClientToken";

const String defaultVoice = "en-US-EmmaMultilingualNeural";

const String chromiumFullVersion = "143.0.3650.75";
final String chromiumMajorVersion = chromiumFullVersion.split(".").first;
const String secMsGecVersion = "1-$chromiumFullVersion";

final Map<String, String> baseHeaders = {
  "User-Agent":
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/$chromiumMajorVersion.0.0.0 Safari/537.36 "
      "Edg/$chromiumMajorVersion.0.0.0",
  "Accept-Encoding": "gzip, deflate, br, zstd",
  "Accept-Language": "en-US,en;q=0.9",
};

const Map<String, String> wssHeadersRaw = {
  "Pragma": "no-cache",
  "Cache-Control": "no-cache",
  "Origin": "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold",
  "Sec-WebSocket-Version": "13",
};

/// WebSocket headers, merged with [baseHeaders].
///
/// Note: `Sec-WebSocket-Version` is included for parity with the Python
/// implementation, but it must be stripped before passing the map to
/// `dart:io`'s WebSocket handshake (which sets it itself).
final Map<String, String> wssHeaders = {...wssHeadersRaw, ...baseHeaders};

final Map<String, String> voiceHeadersRaw = {
  "Authority": "speech.platform.bing.com",
  "Sec-CH-UA": '" Not;A Brand";v="99", "Microsoft Edge";v="$chromiumMajorVersion", '
      '"Chromium";v="$chromiumMajorVersion"',
  "Sec-CH-UA-Mobile": "?0",
  "Accept": "*/*",
  "Sec-Fetch-Site": "none",
  "Sec-Fetch-Mode": "cors",
  "Sec-Fetch-Dest": "empty",
};

/// Voice-list HTTP headers, merged with [baseHeaders].
final Map<String, String> voiceHeaders = {...voiceHeadersRaw, ...baseHeaders};

/// Audio timing constants for CBR-based offset compensation.
///
/// The output format `audio-24khz-48kbitrate-mono-mp3` is a 48 kbps constant
/// bitrate stream. Microsoft's offset/duration metadata uses 100-nanosecond
/// ticks, so 1 second = [ticksPerSecond] ticks.
const int ticksPerSecond = 10000000;
const int mp3BitrateBps = 48000;
