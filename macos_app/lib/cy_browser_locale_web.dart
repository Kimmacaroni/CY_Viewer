import 'package:web/web.dart' as web;

void setBrowserLanguage(String code) {
  web.document.documentElement?.setAttribute('lang', code);
  web.document
      .querySelector('meta[name="apple-mobile-web-app-title"]')
      ?.setAttribute('content', code == 'ko' ? 'CY뷰어' : 'CY Viewer');
  web.document
      .querySelector('link[rel="manifest"]')
      ?.setAttribute(
        'href',
        code == 'ko' ? 'manifest.json' : 'manifest-en.json',
      );
  web.document.title = code == 'ko' ? 'CY뷰어' : 'CY Viewer';
}
