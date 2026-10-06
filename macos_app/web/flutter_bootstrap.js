{{flutter_js}}
{{flutter_build_config}}

// GitHub Pages의 기존 캐시와 새 앱 코드를 구분한다.
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) build.mainJsPath += '?release=document-ui-1.11.0-17';
}
_flutter.loader.load();
