import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,cpSync,readFileSync,writeFileSync,rmSync,mkdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {root,fingerprint} from './evidence.mjs';

test('the composition suite kills keyword overwrite, lost conjunction and lost new-rule mutants',()=>{
  const dir=mkdtempSync(join(tmpdir(),'gargamelle-composition-mutants-'));
  try{
    cpSync(join(root,'build/dev/javascript'),dir,{recursive:true});
    const target=join(dir,'gargamelle/gargamelle.mjs'),original=readFileSync(target,'utf8');
    const start=original.indexOf('function conjoin_object_keyword('),end=original.indexOf('\nfunction ',start+1);
    assert.ok(start>=0&&end>start,'Unique compiled emitter helper must exist');
    assert.equal(original.split('function conjoin_object_keyword(').length,2);
    const helper=original.slice(start,end);
    const replace=(from,to)=>{assert.equal(helper.split(from).length,2,'Unique mutation target');return helper.replace(from,to);};
    const mutations=[
      ['overwrite-existing-keyword','function conjoin_object_keyword(schema, key, value) { return put(schema, key, value); }\n'],
      ['drop-existing-allOf',replace('_block = clauses;','_block = $List$Empty$const;')],
      ['drop-new-assertion',replace('let clauses = _block;','return schema;\n    let clauses = _block;')],
    ];
    writeFileSync(join(dir,'check.mjs'),`import assert from 'node:assert/strict';
import * as s from './gargamelle/gargamelle.mjs';
import {Ok,toList} from './gargamelle/gleam.mjs';
import {runCompositionSuite} from ${JSON.stringify(pathToFileURL(join(root,'verification/composition-suite.mjs')).href)};
const unwrap=r=>{assert.ok(r instanceof Ok);return r[0];};
await runCompositionSuite({s,unwrap,toList});
`);
    const run=()=>spawnSync(process.execPath,['check.mjs'],{cwd:dir,encoding:'utf8',timeout:60000});
    const baseline=run();assert.ifError(baseline.error);assert.equal(baseline.status,0,baseline.stderr);
    const observations=[];
    for(const [name,modified] of mutations){
      writeFileSync(target,original.slice(0,start)+modified+original.slice(end));
      const result=run();writeFileSync(target,original);
      assert.ifError(result.error);assert.notEqual(result.status,0,name+' survived');assert.match(result.stderr,/AssertionError/);
      observations.push({name,status:'killed',exitCode:result.status});
    }
    mkdirSync(join(root,'reports'),{recursive:true});
    writeFileSync(join(root,'reports/composition-mutations.json'),JSON.stringify({status:'passed',source:fingerprint().digest,baseline:'passed',mutants:observations},null,2)+'\n');
  }finally{rmSync(dir,{recursive:true,force:true});}
});
