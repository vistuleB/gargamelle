import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,cpSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {root} from './evidence.mjs';

test('modifier regressions detect rejected names and overwritten array conjunctions',()=>{
 const dir=mkdtempSync(join(tmpdir(),'gargamelle-modifier-mutants-'));
 try{
  cpSync(join(root,'build/dev/javascript'),dir,{recursive:true});
  const path=join(dir,'gargamelle/gargamelle.mjs'),original=readFileSync(path,'utf8');
  const segment=(name)=>{const start=original.indexOf(`function ${name}(`),end=original.indexOf('\nfunction ',start+1);assert.ok(start>=0&&end>start);return {start,end,body:original.slice(start,end)};};
  const wrapper=segment('rewrite_modifier_base'),conjunction=segment('conjoin_schemas');
  assert.equal(wrapper.body.split('} else if (node instanceof NamedNode) {').length,2);
  assert.equal(conjunction.body.split('_block = clauses;').length,2);
  const mutations=[
   {name:'reject-named',...wrapper,modified:wrapper.body.replace('} else if (node instanceof NamedNode) {','} else if (node instanceof NamedNode) { return new Error(new ConstructionError(unsupported));')},
   {name:'overwrite-allOf',...conjunction,modified:conjunction.body.replace('_block = clauses;','_block = $List$Empty$const;')},
  ];
  writeFileSync(join(dir,'check.mjs'),`import assert from 'node:assert/strict';
import * as s from './gargamelle/gargamelle.mjs';
import {Ok} from './gargamelle/gleam.mjs';
import {Some,Option$None$const as None} from './gleam_stdlib/gleam/option.mjs';
const unwrap=r=>{assert.ok(r instanceof Ok);return r[0];};
const named=unwrap(s.named('bounded',s.text()));
const bounded=unwrap(s.bounds(named,new Some(2),None));
assert.equal(s.validate(bounded,unwrap(s.parse('"ab"'))).isOk(),true);
let d=unwrap(s.contains(s.array(s.safe_integer()),unwrap(s.integer_constant(1)),1,None));
d=unwrap(s.unique_items(d));d=s.exclude(d,s.array(unwrap(s.integer_constant(1))));
d=unwrap(s.contains(d,unwrap(s.integer_constant(2)),1,None));
d=unwrap(s.contains(d,unwrap(s.integer_constant(3)),1,None));
const schema=JSON.parse(s.schema_string(d,s.JsonFormat$Compact$const));
// Keep this mutation check independent of external module resolution in the
// temporary tree. A retained allOf base must contain its exclusion clause.
assert.equal(schema.allOf.some(x=>x.not!==undefined),true);
assert.equal(s.validate(d,unwrap(s.parse('[1,2,3]'))).isOk(),true);
assert.equal(s.validate(d,unwrap(s.parse('[2,3,4]'))).isOk(),false);
`);
  const run=()=>spawnSync(process.execPath,['check.mjs'],{cwd:dir,encoding:'utf8',timeout:10000});
  const baseline=run();assert.ifError(baseline.error);assert.equal(baseline.status,0,baseline.stderr);
  for(const m of mutations){
   writeFileSync(path,original.slice(0,m.start)+m.modified+original.slice(m.end));
   const result=run();writeFileSync(path,original);
   assert.ifError(result.error);assert.notEqual(result.status,0,m.name+' survived');assert.match(result.stderr,/AssertionError/);
  }
 }finally{rmSync(dir,{recursive:true,force:true});}
});
