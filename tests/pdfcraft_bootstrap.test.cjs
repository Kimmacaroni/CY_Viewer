// 배포 HTML의 버전이 실제 앱 코드 요청까지 전달되는지 검사한다.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const web=path.resolve(__dirname,'../macos_app/web');
const source=fs.readFileSync(path.join(web,'flutter_bootstrap.js'),'utf8').replace('{{flutter_js}}','').replace('{{flutter_build_config}}','');
function bootstrap(release){
 const builds=[{mainJsPath:'main.dart.js?existing=1'},{}];let loaded=false;
 vm.runInNewContext(source,{URL,document:{baseURI:'https://example.test/CY_Viewer/',currentScript:{src:'https://example.test/CY_Viewer/flutter_bootstrap.js'+release}},_flutter:{buildConfig:{builds},loader:{load(){loaded=true;}}}});
 assert(loaded);return builds;
}
test('HTML의 배포 버전이 main.dart.js에도 적용된다',()=>{
 const html=fs.readFileSync(path.join(web,'index.html'),'utf8');
 const query=html.match(/flutter_bootstrap\.js(\?[^" ]+)/)[1];
 const builds=bootstrap(query),main=new URL(builds[0].mainJsPath);
 assert.equal(main.searchParams.get('release'),new URLSearchParams(query).get('release'));
 assert.equal(main.searchParams.get('existing'),'1');
 assert.equal(main.pathname,'/CY_Viewer/main.dart.js');
 assert.deepEqual(builds[1],{});
});
test('다음 배포는 이전 앱 코드 캐시 주소를 재사용하지 않는다',()=>{
 assert.notEqual(bootstrap('?release=first')[0].mainJsPath,bootstrap('?release=second')[0].mainJsPath);
});
test('배포 쿼리 없이 실행해도 앱을 시작한다',()=>{
 assert.equal(bootstrap('')[0].mainJsPath,'main.dart.js?existing=1');
});

test('전체 작업실 host도 현재 HTML 배포 버전을 요청한다',()=>{
 const html=fs.readFileSync(path.join(web,'index.html'),'utf8');
 const boot=new URL(html.match(/src="([^"]*flutter_bootstrap[^" ]+)"/)[1],'https://example.test/CY_Viewer/');
 const host=new URL(html.match(/src="([^"]*pdf-workbench-host[^" ]+)"/)[1],'https://example.test/CY_Viewer/');
 assert.equal(host.searchParams.get('release'),boot.searchParams.get('release'));
});
