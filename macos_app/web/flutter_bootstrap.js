{{flutter_js}}
{{flutter_build_config}}

// 시작 스크립트와 실제 앱 코드를 같은 배포 주소로 묶는다.
// 홈 화면 앱도 예전 main.dart.js 캐시를 재사용하지 않게 한다.
const appRelease = new URL(document.currentScript.src).searchParams.get('release');
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath && appRelease) {
    const main = new URL(build.mainJsPath, document.baseURI);
    main.searchParams.set('release', appRelease);
    build.mainJsPath = main.href;
  }
}
_flutter.loader.load();
