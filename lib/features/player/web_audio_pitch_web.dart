import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

void setWebAudioPreservesPitch(bool preservesPitch) {
  try {
    final audioElements = web.document.querySelectorAll('audio');
    for (var i = 0; i < audioElements.length; i++) {
      final el = audioElements.item(i);
      if (el != null) {
        final jsObj = el as JSObject;
        jsObj['preservesPitch'] = preservesPitch.toJS;
        jsObj['webkitPreservesPitch'] = preservesPitch.toJS;
        jsObj['mozPreservesPitch'] = preservesPitch.toJS;
      }
    }
  } catch (_) {}
}
