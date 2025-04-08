// html_helper_web.dart
import 'dart:html' as html;
import 'html_helper.dart';

class HtmlHelperImpl implements HtmlHelper {
  @override
  void downloadFile(List<int> bytes, String filename) {
    final blob = html.Blob(
      [bytes],
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.document.createElement('a') as html.AnchorElement
      ..href = url
      ..download = filename
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove(); // Elimina el elemento del DOM
    html.Url.revokeObjectUrl(url);
  }
}

HtmlHelper get htmlHelper => HtmlHelperImpl();
