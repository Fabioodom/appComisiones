// lib/html_helper_web.dart

import 'dart:typed_data';
import 'dart:html' as html;

abstract class HtmlHelper {
  void downloadFile(List<int> bytes, String filename);
}

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
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }
}

HtmlHelper get htmlHelper => HtmlHelperImpl();
