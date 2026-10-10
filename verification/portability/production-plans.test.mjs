import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,cpSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import Ajv2020 from 'ajv/dist/2020.js';
const root=fileURLToPath(new URL('../../',import.meta.url));

test('isolated production library integrates typed plans and validation evidence',(t)=>{
  assert.equal(createHash('sha256').update(readFileSync(join(root,'src/gargamelle.gleam'))).digest('hex'),
    readFileSync(join(root,'verification/portability/integration/baseline.sha256'),'utf8').trim(),
    'production source changed: review and refresh the integration copy');
  const directory=mkdtempSync(join(tmpdir(),'gargamelle-production-plans-'));
  try {
    for(const name of ['src','test','build/packages']) cpSync(join(root,name),join(directory,name),{recursive:true});
    for(const name of ['gleam.toml','manifest.toml']) cpSync(join(root,name),join(directory,name));
    cpSync(join(root,'verification/portability/integration/gargamelle.gleam'),join(directory,'src/gargamelle.gleam'));
    // The old runnable-placeholder contract is retained in the shipped suite;
    // this isolated API instead rejects that use in compile-negative checks.
    rmSync(join(directory,'test/reference_lifetime_test.gleam'));
    for(const name of ['plan_support.erl','plan_support.mjs']) cpSync(join(root,'verification/portability/plans',name),join(directory,'src',name));
    cpSync(join(root,'verification/portability/integration/integration_test.gleam'),join(directory,'test/integration_test.gleam'));
    cpSync(join(root,'verification/portability/integration/integration_probe.gleam'),join(directory,'src/integration_probe.gleam'));
    const basic=[null,false,true,-1,-0,0,1,2.5,9007199254740991,"", "x", "special", "blocked", "ab", "😀"];
    const values=[...basic,[],{},...basic.flatMap(value=>[[value],["x",value],{name:value},{"a/~":value}]),
      ["x","x"],["x","y","x"],["x",true],["x",false],[true,false],
      [null,null],[0,-0],{name:"x",enabled:false},{value:"x"},{kind:"leaf",value:1.25},
      {kind:"branch",children:[{kind:"leaf",value:1.25}]},
      {kind:"branch",children:[{kind:"leaf",value:"bad"}]},
      JSON.parse('{"__proto__":"safe","constructor":"x"}'),{a:1},{"a/~":1},{items:[]},
      [[],[[]]], ["x",["y"]], {name:"x",extra:1}, {tree:[]}, {children:[]}];
    const sources=values.map(value=>JSON.stringify(value));
    sources.push('{"z":"first","a":"middle","z":"last"}',
      '{"4294967295":"max","01":"leading","10":"ten","2":"two","0":"zero","4294967294":"lastindex","b":"b","a":"a"}',
      '{"outer":{"z":"old","a":"middle","z":"new"}}');
    writeFileSync(join(directory,'src/integration_inputs.gleam'),`pub fn values() -> List(String) { [${sources.map(value=>JSON.stringify(value)).join(',')}] }\n`);
    cpSync(join(root,'verification/portability/integration/integration_benchmark.gleam'),join(directory,'src/integration_benchmark.gleam'));
    cpSync(join(root,'verification/portability/integration/integration_walk.mjs'),join(directory,'src/integration_walk.mjs'));
    const run=(args)=>spawnSync('gleam',args,{cwd:directory,encoding:'utf8',timeout:60000,maxBuffer:5*1024*1024,env:{...process.env,GIT_DIR:'',GIT_WORK_TREE:''}});
    const javascript=run(['test','--target','javascript']);
    assert.equal(javascript.status,0,javascript.stderr+'\n'+javascript.stdout);
    assert.match(javascript.stdout,/42 passed, no failures/);
    const probe=target=>{
      const result=run(['run','--target',target,'-m','integration_probe']);
      assert.equal(result.status,0,result.stderr+'\n'+result.stdout);
      return JSON.parse(result.stdout.trim());
    };
    const benchmark=target=>{
      const result=run(['run','--target',target,'-m','integration_benchmark']);
      assert.equal(result.status,0,result.stderr+'\n'+result.stdout);
      const costs=JSON.parse(result.stdout.trim());
      assert.equal(costs.length,4);
      t.diagnostic(`${target}: bounded production costs (no timing thresholds): ${JSON.stringify(costs)}`);
    };
    const integrated=probe('javascript');
    benchmark('javascript');
    const integratedSource=readFileSync(join(directory,'src/gargamelle.gleam'));
    rmSync(join(directory,'test/integration_test.gleam'));
    cpSync(join(root,'src/gargamelle.gleam'),join(directory,'src/gargamelle.gleam'));
    assert.deepEqual(probe('javascript'),integrated,'schema bytes, decoded outputs or full DataError structures changed');
    writeFileSync(join(directory,'src/gargamelle.gleam'),integratedSource);
    cpSync(join(root,'verification/portability/integration/integration_test.gleam'),join(directory,'test/integration_test.gleam'));
    const ajv=new Ajv2020({strict:false,allErrors:true,ownProperties:true});
    for(const fixture of integrated) {
      const validate=ajv.compile(JSON.parse(fixture.schema));
      for(const entry of fixture.cases) {
        assert.equal(validate(JSON.parse(entry.input)),entry.accepted,fixture.name+': '+entry.input);
        assert.equal(entry.decoded!==null,entry.accepted);
      }
    }
    cpSync(join(root,'verification/portability/scalar_api.erl'),join(directory,'src/scalar_api.erl'));
    let graph=readFileSync(join(root,'verification/portability/graph_api_test.gleam'),'utf8');
    graph=graph.replace('import reference_lifetime_test.{Captured}\n','');
    graph=graph.slice(0,graph.indexOf('pub fn captured_placeholder_handoff_test()'))+graph.slice(graph.indexOf('pub fn process_handoff_test()'));
    graph=graph.replace('s.map(s.array(self), Tree), first','s.map(s.array(self), Tree), s.lift(first)');
    graph=graph.replaceAll('s.Definition(String)','s.Plan(String, recursion)');
    writeFileSync(join(directory,'test/graph_api_test.gleam'),graph);
    const source=join(directory,'src/gargamelle.gleam');
    let text=readFileSync(source,'utf8');
    for(const name of ['pattern_valid','pattern_matches']) {
      const marker=`@external(javascript, "./runtime.mjs", "${name}")`;
      assert.equal(text.split(marker).length-1,1);
      text=text.replace(marker,`@external(erlang, "scalar_api", "${name}")\n${marker}`);
    }
    writeFileSync(source,text);
    const fixtures=join(directory,'src/schema_fixtures.gleam');
    writeFileSync(fixtures,readFileSync(fixtures,'utf8').replace('@external(javascript, "./runtime.mjs", "int_text")',
      '@external(erlang, "gargamelle_runtime", "int_text")\n@external(javascript, "./runtime.mjs", "int_text")'));
    const erlang=run(['test','--target','erlang']);
    assert.equal(erlang.status,0,erlang.stderr+'\n'+erlang.stdout);
    assert.match(erlang.stdout,/49 passed, no failures/);
    assert.deepEqual(probe('erlang'),integrated,'cross-target schema/output/diagnostic mismatch');
    benchmark('erlang');
    for(const [name,body,privateValue] of [
      ['decode','s.decode(self, value)',false],
      ['validate','s.validate(self, value)',false],
      ['emit','s.emit_text(self)',false],
      ['render','documentation.render(self, "test")',false],
      ['private-evidence','s.Atomic',true],
      ['private-runner','s.Recursive(fn(_, _) { Nil })',true],
    ]) {
      writeFileSync(join(directory,'src/negative.gleam'),`import gargamelle as s
import gargamelle/documentation
pub fn forbidden() {
  let assert Ok(value) = s.parse("[]")
  s.recursive("bad", fn(self) {
    ${body}
    Ok(s.map(s.array(self), fn(_) { Nil }))
  })
}\n`);
      for(const target of ['javascript','erlang']) {
        const result=run(['build','--target',target]);
        assert.notEqual(result.status,0,`${name} unexpectedly compiled on ${target}`);
        assert.match(result.stderr,privateValue?/Unknown module value/:/Type mismatch/);
        assert.match(result.stderr,privateValue?(name==='private-evidence'?/Atomic/:/Recursive/):/Plan/);
      }
    }
    t.diagnostic('12 compile-negative checks passed on the integrated API');
    t.diagnostic(`${integrated.length} schemas, ${integrated.reduce((sum,row)=>sum+row.cases.length,0)} independent cases; exact shipped JavaScript and native comparison`);
    t.diagnostic('37 shared production tests, five integration tests and seven native process/graph tests passed');
  } finally {rmSync(directory,{recursive:true,force:true});}
});
