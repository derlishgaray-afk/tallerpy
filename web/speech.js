// web/speech.js
(function () {
  let rec = null;

  let cbPartial = null;
  let cbFinal = null;
  let cbStatus = null;
  let cbError = null;

  // Anti-duplicado
  let lastFinal = "";
  let lastFinalTs = 0;

  let lastPartial = "";

  function norm(s) {
    return String(s || "")
      .trim()
      .toLowerCase()
      .replace(/\s+/g, " ");
  }

  function shouldIgnoreFinal(t) {
    const n = norm(t);
    const now = Date.now();

    // mismo final dentro de 1200ms => ignorar
    if (n && n === lastFinal && now - lastFinalTs < 1200) return true;

    lastFinal = n;
    lastFinalTs = now;
    return false;
  }

  function shouldIgnorePartial(t) {
    const n = norm(t);
    if (!n) return true;

    // si el partial no cambió, no lo re-envíes
    if (n === lastPartial) return true;
    lastPartial = n;
    return false;
  }

  window.speechIsSupported = function () {
    return !!(window.SpeechRecognition || window.webkitSpeechRecognition);
  };

  window.speechBindCallbacks = function (onPartial, onFinal, onStatus, onError) {
    cbPartial = onPartial;
    cbFinal = onFinal;
    cbStatus = onStatus;
    cbError = onError;
  };

  window.speechStart = function (localeId) {
    if (!window.speechIsSupported()) {
      cbError && cbError("SpeechRecognition no soportado en este navegador.");
      return;
    }

    window.speechStop(); // corta sesión anterior si existía

    // reset dedupe al iniciar
    lastFinal = "";
    lastFinalTs = 0;
    lastPartial = "";

    const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
    rec = new SR();
    rec.lang = localeId || "es-ES";
    rec.continuous = false; // ✅ mejor para evitar repeticiones
    rec.interimResults = true;

    rec.onstart = function () {
      cbStatus && cbStatus("started");
    };

    rec.onend = function () {
      cbStatus && cbStatus("stopped");
    };

    rec.onerror = function (e) {
      cbStatus && cbStatus("error");
      cbError && cbError(e && e.error ? String(e.error) : "error");
    };

    rec.onresult = function (event) {
      // si rec ya fue cortado, ignorar resultados tardíos
      if (!rec) return;

      const i = event.results.length - 1;
      const result = event.results[i];
      if (!result || !result[0]) return;

      const transcript = (result[0].transcript || "").trim();
      if (!transcript) return;

      if (result.isFinal) {
        if (shouldIgnoreFinal(transcript)) return;
        cbFinal && cbFinal(transcript);
      } else {
        if (shouldIgnorePartial(transcript)) return;
        cbPartial && cbPartial(transcript);
      }
    };

    try {
      rec.start(); // debe ser por gesto del usuario
    } catch (e) {
      cbStatus && cbStatus("error");
      cbError && cbError("No se pudo iniciar dictado: " + e);
    }
  };

  window.speechStop = function () {
    if (!rec) return;

    // desconectamos handlers para evitar callbacks tardíos
    try {
      rec.onstart = null;
      rec.onend = null;
      rec.onerror = null;
      rec.onresult = null;
      rec.stop();
    } catch (_) {}

    rec = null;
  };
})();
