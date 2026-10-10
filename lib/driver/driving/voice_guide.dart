import 'package:flutter_tts/flutter_tts.dart';

import '../../util/app_log.dart';

/// The driving screen's voice: the phone's own speech engine, so it works with
/// no signal. New Zealand English where the phone has it.
///
/// Lines queue: "Next: Otago Glass" and "Continue for 600 metres, then turn
/// left" arrive together and are both said, in order. An [urgent] line - the
/// turn itself, "Turn left onto King St" - drops whatever is waiting and
/// speaks at once, because by the time a queued line got to it the turn would
/// be behind the van. [muted] is the driver's choice (the voice button, and
/// the "Voice prompts" setting).
class VoiceGuide {
  VoiceGuide();

  final _tts = FlutterTts();
  final _queue = <String>[];
  bool _speaking = false;
  bool _ready = false;
  bool _muted = false;

  bool get muted => _muted;
  set muted(bool value) {
    _muted = value;
    if (value) stop();
  }

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
      _tts.setCompletionHandler(_next);
      _tts.setCancelHandler(() => _speaking = false);
      _tts.setErrorHandler((_) => _next());
    } catch (error, stack) {
      AppLog.auth.error('voice setup failed', error, stack);
    }
  }

  Future<void> say(String text, {bool urgent = false}) async {
    if (_muted || text.isEmpty) return;
    await _prepare();
    if (urgent) {
      _queue.clear();
      await _speak(text);
      return;
    }
    _queue.add(text);
    if (!_speaking) _next();
  }

  void _next() {
    _speaking = false;
    if (_muted || _queue.isEmpty) return;
    _speak(_queue.removeAt(0));
  }

  Future<void> _speak(String text) async {
    try {
      _speaking = true;
      await _tts.stop();
      await _tts.speak(text);
    } catch (error, stack) {
      _speaking = false;
      AppLog.auth.error('voice failed', error, stack);
    }
  }

  Future<void> stop() async {
    _queue.clear();
    _speaking = false;
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
