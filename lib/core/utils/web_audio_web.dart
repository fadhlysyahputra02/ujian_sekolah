import 'dart:js_interop';

@JS('eval')
external void _jsEval(String code);

void playWebBeep(bool isSuccess) {
  if (isSuccess) {
    // 1x pleasant "tut" tone
    final code = '''
      (function() {
        try {
          var ctx = new (window.AudioContext || window.webkitAudioContext)();
          var osc = ctx.createOscillator();
          var gain = ctx.createGain();
          osc.type = 'sine';
          osc.frequency.value = 880;
          gain.gain.value = 0.3;
          osc.connect(gain);
          gain.connect(ctx.destination);
          osc.start();
          osc.stop(ctx.currentTime + 0.10);
        } catch(e) {}
      })();
    ''';
    _jsEval(code);
  } else {
    // 2x rapid pleasant "tut-tut" tone
    final code = '''
      (function() {
        try {
          var ctx = new (window.AudioContext || window.webkitAudioContext)();
          
          var osc1 = ctx.createOscillator();
          var gain1 = ctx.createGain();
          osc1.type = 'sine';
          osc1.frequency.value = 880;
          gain1.gain.value = 0.3;
          osc1.connect(gain1);
          gain1.connect(ctx.destination);
          osc1.start(ctx.currentTime);
          osc1.stop(ctx.currentTime + 0.08);

          var osc2 = ctx.createOscillator();
          var gain2 = ctx.createGain();
          osc2.type = 'sine';
          osc2.frequency.value = 880;
          gain2.gain.value = 0.3;
          osc2.connect(gain2);
          gain2.connect(ctx.destination);
          osc2.start(ctx.currentTime + 0.12);
          osc2.stop(ctx.currentTime + 0.20);
        } catch(e) {}
      })();
    ''';
    _jsEval(code);
  }
}
