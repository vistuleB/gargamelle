// Opt-in research gate: external pinned QuickJS sources, no package dependency.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync,mkdtempSync,rmSync,mkdirSync,cpSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {isDeepStrictEqual} from 'node:util';
const root=fileURLToPath(new URL('../../',import.meta.url));
let source=process.argv[2];
if (!source) throw new Error('Usage: node verification/portability/quickjs-probe.mjs /path/to/quickjs-source');
assert.equal(process.versions.unicode,'16.0','Reference Unicode version changed; review the corpus');
const version=readFileSync(join(source,'VERSION'),'utf8').trim();
assert.ok(['2025-09-13','2026-06-04'].includes(version),'Unreviewed QuickJS source version');
const directory=mkdtempSync(join(tmpdir(),'gargamelle-quickjs-'));
const unicodeSource=process.argv[3];
const variant=unicodeSource?'unicode16-overlay':'original';
const sanitized=process.env.PROBE_SANITIZERS==='1';
if(unicodeSource) {
  assert.equal(version,'2026-06-04');
  assert.equal(readFileSync(join(unicodeSource,'VERSION'),'utf8').trim(),'2025-09-13');
  cpSync(source,join(directory,'source'),{recursive:true});
  source=join(directory,'source');
  for(const name of ['libunicode-table.h','unicode_gen_def.h'])
    cpSync(join(unicodeSource,name),join(source,name));
}
const hashes=Object.fromEntries(['VERSION','libregexp.c','libregexp.h','libregexp-opcode.h','libunicode.c','libunicode.h','libunicode-table.h','unicode_gen_def.h','cutils.c','cutils.h'].map(name=>[
  name,createHash('sha256').update(readFileSync(join(source,name))).digest('hex'),
]));
function run(command,args,options={}) {
  const result=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:60000,maxBuffer:30*1024*1024,...options});
  if(result.error) throw new Error(`${result.error}\n${result.stdout?.slice(-1000)}\n${result.stderr}`);
  assert.equal(result.status,0,result.stdout+'\n'+result.stderr);
  return result.stdout;
}
try {
  const executable=join(directory,'regex-probe');
  run(process.env.CC??'clang',['-O2',...(sanitized?['-fsanitize=address,undefined','-fno-omit-frame-pointer']:[]),...(version==='2026-06-04'?['-DPROBE_NEW_REGISTERS']:[]),'-I',resolve(source),'verification/portability/quickjs_regex_probe.c',
    ...['libregexp.c','libunicode.c','cutils.c'].map(name=>resolve(source,name)),'-o',executable]);
  const patterns=[
    '', '.', '^.$', '^..$', '^a$', '\\s', '\\S', '\\w', '\\W', '\\d', '\\D', '\\b', '\\B',
    'a|b','[a-z]+','[^a-z]','a*','a+?','a{0,2}','(?:ab)+','(a)\\1','(a)?\\1',
    '(?=a)a','(?!a).','(?<=a)b','(?<!a)b','(?<item>a)\\k<item>',
    '(?<item>a)|(?<item>b)','(?<item>a)(?<item>b)',
    '(?:(?<item>a)|(?<item>b))\\k<item>','(?:(?<item>a)|(?<item>b))+\\k<item>',
    '(?:(?<item>a)|(?<item>b))\\1\\2','(?<item>a)|(?<item>b)|(?<item>ab)',
    '(?:(?<item>a)|(?<item>b))?(?<item>ab)','(?<é>a)\\k<é>',
    '(a|(b))+\\2','(?<=([ab]+)([bc]+))$','(?i:a)','(?s:.)','(?m:^a$)',
    '\\u{1F49C}','\\uD800','\\uDC00','[\\uD800-\\uDFFF]',
    '\\p{L}+','\\p{Letter}','\\p{Script=Greek}','\\p{Script_Extensions=Hiragana}',
    '\\p{Emoji}','\\p{Surrogate}','\\p{Assigned}','\\P{White_Space}',
    '\\a','(?i)a','[','[z-a]','a{2,1}','\\1','\\8','\\c','\\xZ0','\\u{110000}',
    '\\p{Unknown}','\\p{letter}','[a-\\d]','[\\-]','\\-','(?<a>a)\\k<b>',
    '*','a++','(?>a)','(?|a)','(?<1>a)','\\0','\\00','^💜$','[💜-💙]',
  ];
  const texts=['','a','b','ab','aa','a\n','a\r','a\r\n','a\u2028','\n','\r','\u2028','\u2029',
    '\ufeff','\u00a0','\u0085','\u0000','\t','é','e\u0301','ß','α','あ','💜','💜💙',
    '\ud800','\udfff','\ud800a','a\udfff','\ud800\ud800','\udc00\ud800','\ud800\udc00',
    '__proto__',String.fromCodePoint(0x105c0),String.fromCodePoint(0x11f02),String.fromCodePoint(0x11db0)];
  const cases=patterns.flatMap(pattern=>texts.map(text=>({pattern,text})));
  let state=0x67617267;
  const random=()=>{state^=state<<13;state^=state>>>17;state^=state<<5;return state>>>0;};
  const atoms=['a','b','é','💜','[a-z]','[0-9]','[^a]','\\s','\\S','\\w','\\d','.','\\uD800','\\p{L}'];
  for(let i=0;i<1200;i++) {
    const a=atoms[random()%atoms.length],b=atoms[random()%atoms.length];
    const pattern=[`(${a}|${b})+`,`(?:${a}){0,3}${b}?`,`(?=${a})${b}`,`(?<=${a})${b}`,`^${a}*${b}$`][random()%5];
    let text='';for(let j=0,n=random()%8;j<n;j++)text+=texts[random()%texts.length];
    cases.push({pattern,text});
  }
  const properties=['L','Nd','Assigned','Emoji','Script=Greek','Script_Extensions=Hiragana'];
  for(let i=0;i<1600;i++) {
    const cp=i<256?0x105c0+i:i<512?0x11db0+i-256:random()%0x110000;
    for(const property of properties)cases.push({pattern:`^\\p{${property}}$`,text:String.fromCodePoint(cp)});
  }
  const requests=cases.map(({pattern,text})=>({pattern,text_utf16:Buffer.from(text,'utf16le').toString('hex').toUpperCase()}));
  requests.push({pattern:'(a+)+$',text_utf16:Buffer.from('a'.repeat(30)+'!','utf16le').toString('hex').toUpperCase(),budget:0});
  requests.push({pattern:'a',text_utf16:'6100'}); // port remains usable after failure
  const output=run('escript',['verification/portability/quickjs_regex_port.escript',executable],{
    input:requests.map(request=>JSON.stringify(request)).join('\n')+'\n',
  }).trim().split('\n').map(line=>JSON.parse(line));
  assert.equal(output.length,requests.length);
  const differences=[];
  for(let i=0;i<cases.length;i++) {
    const {pattern,text}=cases[i];let expected;
    try{expected={valid:true,matched:new RegExp(pattern,'u').test(text)};}
    catch(error){if(!(error instanceof SyntaxError))throw error;expected={valid:false};}
    if(!isDeepStrictEqual(output[i],expected)) differences.push({...cases[i],expected,native:output[i]});
  }
  assert.deepEqual(output.at(-2),{error:'operational'});
  assert.deepEqual(output.at(-1),{valid:true,matched:true});
  const report={version,variant,sanitized,sourceHashes:hashes,node:process.version,unicode:process.versions.unicode,
    cases:cases.length,differences,operationalFailureRetained:true,scope:'Standalone libregexp via an OTP port; research only, no production binding'};
  mkdirSync(join(root,'reports'),{recursive:true});
  writeFileSync(join(root,`reports/quickjs-regex-${version}-${variant}${sanitized?'-sanitized':''}.json`),JSON.stringify(report,null,2)+'\n');
  console.log(`QuickJS/Node regex probe: ${cases.length} cases; ${differences.length} differences; operational failure preserved.`);
  if(differences.length){console.log(JSON.stringify(differences.slice(0,8),null,2));process.exitCode=1;}
} finally {rmSync(directory,{recursive:true,force:true});}
