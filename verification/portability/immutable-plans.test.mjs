import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,cpSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import Ajv2020 from 'ajv/dist/2020.js';
const root=fileURLToPath(new URL('../../',import.meta.url));

test('isolated immutable plans compile and run on JavaScript and Erlang',(t)=>{
  const directory=mkdtempSync(join(tmpdir(),'gargamelle-immutable-plans-'));
  try {
    cpSync(join(root,'build/packages'),join(directory,'build/packages'),{recursive:true});
    for(const name of ['gleam.toml','manifest.toml']) cpSync(join(root,name),join(directory,name));
    cpSync(join(root,'verification/portability/plans'),join(directory,'src'),{recursive:true});
    cpSync(join(directory,'src/plan_test.gleam'),join(directory,'test/plan_test.gleam'));
    // Avoid a second copy of the test module in src.
    rmSync(join(directory,'src/plan_test.gleam'));
    writeFileSync(join(directory,'test/gargamelle_test.gleam'), 'import gleeunit\npub fn main() { gleeunit.main() }\n');
    const run=(args)=>spawnSync('gleam',args,{
      cwd:directory,encoding:'utf8',timeout:60000,maxBuffer:5*1024*1024,
      env:{...process.env,GIT_DIR:'',GIT_WORK_TREE:''},
    });
    let previous;
    for(const target of ['javascript','erlang']) {
      const result=run(['test','--target',target]);
      assert.equal(result.status,0,target+'\n'+result.stderr+'\n'+result.stdout);
      assert.match(result.stdout,/20 passed, no failures/);
      const probe=run(['run','--target',target,'-m','plan_probe']);
      assert.equal(probe.status,0,probe.stderr+'\n'+probe.stdout);
      const fixtures=JSON.parse(probe.stdout.trim());
      if(previous) assert.deepEqual(fixtures,previous,'cross-target schema and acceptance mismatch');
      previous=fixtures;
      const ajv=new Ajv2020({strict:false});
      for(const fixture of fixtures) {
        const validator=ajv.compile(JSON.parse(fixture.schema));
        for(const entry of fixture.cases) {
          assert.equal(validator(entry.value),entry.accepted,`${target}: ${fixture.name}: ${JSON.stringify(entry.value)}`);
          assert.equal(entry.decoded,entry.accepted);
        }
      }
      t.diagnostic(`${target}: 20 behavioral tests; ${fixtures.reduce((sum,fixture)=>sum+fixture.cases.length,0)} independent schema cases`);
      const benchmark=run(['run','--target',target,'-m','plan_benchmark']);
      assert.equal(benchmark.status,0,benchmark.stderr+'\n'+benchmark.stdout);
      const costs=JSON.parse(benchmark.stdout.trim());
      assert.equal(costs.length,15);
      t.diagnostic(`${target} bounded costs (observations, no timing thresholds): ${JSON.stringify(costs)}`);
    }
    for(const [name,body,privateValue] of [
      ['decode','p.decode(self, p.Text("x"))'],
      ['finish','p.finish(self)'],
      ['finish-mapped','p.finish(p.map(self, fn(_) { Nil }))'],
      ['finish-tuple','p.finish(plan_helpers.packet(self))'],
      ['private-evidence','p.Atomic',true],
      ['private-runner','p.Recursive(fn(_, _) { Nil })',true],
    ]) {
      writeFileSync(join(directory,'src/negative.gleam'), `import immutable_plan as p
import plan_helpers
pub fn forbidden() {
  p.recursive("bad", fn(self) {
    ${body}
    Ok(p.map(p.text(), fn(_) { Nil }))
  })
}
`);
      for(const target of ['javascript','erlang']) {
        const result=run(['build','--target',target]);
        assert.notEqual(result.status,0,`${name} unexpectedly compiled on ${target}`);
        if(privateValue) {
          assert.match(result.stderr,/Unknown module value/);
          assert.match(result.stderr,name==='private-evidence'?/Atomic/:/Recursive/);
        } else {
          assert.match(result.stderr,/Type mismatch/);
          assert.match(result.stderr,/Plan/);
        }
      }
    }
  } finally {rmSync(directory,{recursive:true,force:true});}
});
