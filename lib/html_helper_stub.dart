// lib/html_helper_stub.dart

import 'dart:typed_data';

abstract class HtmlHelper {
  void downloadFile(List<int> bytes, String filename);
}

class HtmlHelperStub implements HtmlHelper {
  @override
  void downloadFile(List<int> bytes, String filename) {
    // No hay descarga en móviles; podrías lanzar si prefieres:
    // throw UnimplementedError('downloadFile() solo disponible en Web');
  }
}

// Lo importante: exponemos la misma API
HtmlHelper get htmlHelper => HtmlHelperStub();
