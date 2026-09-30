{{flutter_js}}
{{flutter_build_config}}

// GitHub Pages의 기존 캐시와 새 앱 코드를 구분한다.
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) build.mainJsPath += '?release=mac-ui-1.10.1-16';
}
_flutter.loader.load();
