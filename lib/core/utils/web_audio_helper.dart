import 'package:sys_exam_school/core/utils/web_audio_stub.dart'
    if (dart.library.js_interop) 'package:sys_exam_school/core/utils/web_audio_web.dart';

void triggerWebAudioBeep(bool isSuccess) {
  playWebBeep(isSuccess);
}
