// html_helper.dart
abstract class HtmlHelper {
  void downloadFile(List<int> bytes, String filename);
}

// La instancia 'htmlHelper' se definirá en la implementación condicional.
HtmlHelper get htmlHelper => throw UnimplementedError('htmlHelper not implemented');
