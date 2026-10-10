import 'package:flutter_tts/flutter_tts.dart';

import '../../util/app_log.dart';

/// The driving screen's voice: the phone's own speech engine, so it works with
/// no signal. New Zealand English where the phone has it.
///
/// One thing at a time: a new line interrupts the last, because the latest
/// news ("Approaching ...") is the one that matters. [muted] is the driver's
/// choice (the mute button, and the "Voice prompts" setting).
class VoiceGuide {
  VoiceGuide();

  final _tts = FlutterTts();
  bool muted = false;
  bool _ready = false;

  Future<void> _prepare() async {
    if (_ready) return;
    _ready = true;
    try {
      for (final language in const ['en-NZ', 'en-AU', 'en-GB', 'en-US']) {
        if (await _tts.isLanguageAvailable(language) == true) {
          await _tts.setLanguage(language);
          break;
        }
      }
      await _tts.setSpeechRate(0.5);
      await _tts.awaitSpeakCompletion(false);
    } catch (error, stack) {
      AppLog.auth.error('voice setup failed', error, stack);
    }
  }

  Future<void> say(String text) async {
    if (muted || text.isEmpty) return;
    await _prepare();
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (error, stack) {
      AppLog.auth.error('voice failed', error, stack);
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
