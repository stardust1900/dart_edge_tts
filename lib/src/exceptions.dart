/// Custom exceptions for the edge_tts package.
///
/// Ported from Python `edge_tts/exceptions.py`.
library;

/// Base exception for the edge_tts package.
class EdgeTTSException implements Exception {
  /// A human-readable message describing the error.
  final String message;

  /// Creates an [EdgeTTSException] with the given [message].
  EdgeTTSException(this.message);

  @override
  String toString() => message;
}

/// Raised when an unknown response is received from the server.
class UnknownResponse extends EdgeTTSException {
  /// Creates an [UnknownResponse] with the given [message].
  UnknownResponse(super.message);
}

/// Raised when an unexpected response is received from the server.
class UnexpectedResponse extends EdgeTTSException {
  /// Creates an [UnexpectedResponse] with the given [message].
  UnexpectedResponse(super.message);
}

/// Raised when no audio is received from the server.
class NoAudioReceived extends EdgeTTSException {
  /// Creates a [NoAudioReceived] with the given [message].
  NoAudioReceived(super.message);
}

/// Raised when a WebSocket error occurs.
class WebSocketError extends EdgeTTSException {
  /// Creates a [WebSocketError] with the given [message].
  WebSocketError(super.message);
}

/// Raised when an error occurs while adjusting the clock skew.
class SkewAdjustmentError extends EdgeTTSException {
  /// Creates a [SkewAdjustmentError] with the given [message].
  SkewAdjustmentError(super.message);
}
