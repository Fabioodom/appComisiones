// html_helper_stub.dart
import 'html_helper.dart';

class HtmlHelperStub implements HtmlHelper {
  @override
  void downloadFile(List<int> bytes, String filename) {
    // No se usa en plataformas no web.
    // También puedes lanzar un error si lo prefieres:
    // throw UnimplementedError('downloadFile() is not available on this platform.');
  }
}

HtmlHelper get htmlHelper => HtmlHelperStub();
