// lib/utils/speech_web_impl.dart
@JS()

import 'dart:js_interop';

/// Estas funciones existen en web/speech.js
@JS('speechIsSupported')
external bool _speechIsSupported();

@JS('speechBindCallbacks')
external void _speechBindCallbacks(
  JSFunction onPartial,
  JSFunction onFinal,
  JSFunction onStatus,
  JSFunction onError,
);

@JS('speechStart')
external void _speechStart(String localeId);

@JS('speechStop')
external void _speechStop();

class SpeechWebImpl {
  static void Function(String text)? _onPartial;
  static void Function(String text)? _onFinal;
  static void Function(String status)? _onStatus;
  static void Function(String message)? _onError;

  static bool isSupported() => _speechIsSupported();

  static void setCallbacks({
    required void Function(String text) onPartial,
    required void Function(String text) onFinal,
    required void Function(String status) onStatus,
    required void Function(String message) onError,
  }) {
    _onPartial = onPartial;
    _onFinal = onFinal;
    _onStatus = onStatus;
    _onError = onError;

    // Enlazamos callbacks que speech.js va a invocar
    _speechBindCallbacks(
      ((String t) => _onPartial?.call(t)).toJS,
      ((String t) => _onFinal?.call(t)).toJS,
      ((String s) => _onStatus?.call(s)).toJS,
      ((String m) => _onError?.call(m)).toJS,
    );
  }

  static void start({required String localeId}) {
    _speechStart(localeId);
  }

  static void stop() {
    _speechStop();
  }
}
