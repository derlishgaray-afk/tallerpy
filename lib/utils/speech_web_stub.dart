// lib/utils/speech_web_stub.dart
class SpeechWebImpl {
  static bool isSupported() => false;

  static void setCallbacks({
    required void Function(String text) onPartial,
    required void Function(String text) onFinal,
    required void Function(String status) onStatus,
    required void Function(String message) onError,
  }) {
    // no-op
  }

  static void start({String localeId = 'es-ES'}) {
    // no-op
  }

  static void stop() {
    // no-op
  }
}
