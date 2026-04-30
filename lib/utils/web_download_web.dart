import 'package:universal_html/html.dart' as html;

void webDownload(String dataUrl, String filename) {
  html.AnchorElement(href: dataUrl)
    ..setAttribute('download', filename)
    ..click();
}