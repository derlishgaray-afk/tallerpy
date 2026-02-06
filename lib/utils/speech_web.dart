// lib/utils/speech_web.dart
import 'speech_web_stub.dart' if (dart.library.html) 'speech_web_impl.dart';

abstract class SpeechWeb {
  static bool isSupported() => SpeechWebImpl.isSupported();

  static void setCallbacks({
    required void Function(String text) onPartial,
    required void Function(String text) onFinal,
    required void Function(String status) onStatus,
    required void Function(String message) onError,
  }) => SpeechWebImpl.setCallbacks(
    onPartial: onPartial,
    onFinal: onFinal,
    onStatus: onStatus,
    onError: onError,
  );

  static void start({String localeId = 'es-ES'}) =>
      SpeechWebImpl.start(localeId: localeId);

  static void stop() => SpeechWebImpl.stop();
}
