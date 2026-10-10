import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,cpSync,mkdirSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const root=fileURLToPath(new URL('../../',import.meta.url));
test('production native regex preserves syntax/search and operational failures',(t)=>{
  const directory=mkdtempSync(join(tmpdir(),'gargamelle-native-regex-'));
  const pkg=join(directory,'gargamelle');
  const run=(cmd,args,cwd=root)=>{
    const r=spawnSync(cmd,args,{cwd,encoding:'utf8',timeout:60000,maxBuffer:5*1024*1024});
    assert.ifError(r.error);assert.equal(r.status,0,r.stdout+'\n'+r.stderr);return r.stdout;
  };
  try {
    const provenance=JSON.parse(readFileSync(join(root,'priv/regex-src/PROVENANCE.json')));
    for(const [name,record] of Object.entries(provenance.files))
      assert.equal(createHash('sha256').update(readFileSync(join(root,'priv/regex-src',name))).digest('hex'),record.vendoredSha256,name);
    run('gleam',['build','--target','erlang']);
    cpSync(join(root,'build/dev/erlang/gargamelle/ebin'),join(pkg,'ebin'),{recursive:true});
    cpSync(join(root,'priv'),join(pkg,'priv'),{recursive:true});
    run('make',['-C','priv/regex-src'],pkg);
    const patterns=['','.', '^.$','\\s','\\w','\\p{L}', '\\p{Assigned}','\\p{Script=Greek}',
      '\\p{Script_Extensions=Hiragana}','(?<x>a)|(?<x>b)','(?:(?<x>a)|(?<x>b))\\k<x>',
      '(?<=a)b','(?<!a)b','(a)?\\1','(?s:.)','(?i:a)','(?m:^a$)','^💜$',
      '\\p{IDS_Unary_Operator}','\\p{IDSU}','\\p{Modifier_Combining_Mark}','\\p{MCM}',
      '\\P{IDS_Unary_Operator}','\\P{IDSU}','\\P{Modifier_Combining_Mark}','\\P{MCM}',
      '[','\\a','\\p{letter}','a{2,1}','(?<x>a)(?<x>b)','[a-\\d]','\\uD800'];
    const texts=['','a','b','aa','bb','ab','A','a\n','\n','\u2028','\ufeff','\u0085','é','α','あ','💜',
      String.fromCodePoint(0x105c0),String.fromCodePoint(0x11db0)];
    const cases=patterns.flatMap(pattern=>texts.map(text=>({pattern,text})));
    mkdirSync(join(pkg,'inputs'));
    const input=join(pkg,'inputs/cases.json');writeFileSync(input,JSON.stringify(cases));
    const result=JSON.parse(run('escript',['verification/portability/regex-backend.escript',pkg,root,input]));
    assert.deepEqual(result.cases,cases.map(({pattern,text})=>{
      try {return {valid:true,matched:new RegExp(pattern,'u').test(text)};}
      catch(error){assert.ok(error instanceof SyntaxError);return {valid:false};}
    }));
    for(const flag of Object.values(result.failures)) assert.equal(flag,true);
    assert.equal(result.ports_restored,true);assert.equal(result.mailbox_restored,true);
    assert.equal(result.scoped_cases_equal,true);assert.equal(result.dictionary_restored,true);
    assert.equal(result.flags_restored,true);
    t.diagnostic(`${cases.length} cases through the production binding; ${Math.round(result.microseconds/cases.length)} microseconds/case including helper starts (observation, no threshold)`);
  } finally {rmSync(directory,{recursive:true,force:true});}
});
