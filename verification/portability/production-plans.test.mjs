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

test('main library preserves baseline behavior with immutable recursive plans',(t)=>{
  assert.equal(createHash('sha256').update(readFileSync(join(root,'verification/portability/integration/baseline.gleam'))).digest('hex'),
    readFileSync(join(root,'verification/portability/integration/baseline.sha256'),'utf8').trim(),
    'historical baseline source changed');
  const directory=mkdtempSync(join(tmpdir(),'gargamelle-production-plans-'));
  try {
    for(const name of ['src','test','priv','build/packages']) cpSync(join(root,name),join(directory,name),{recursive:true});
    for(const name of ['gleam.toml','manifest.toml']) cpSync(join(root,name),join(directory,name));
    for(const name of ['plan_support.erl','plan_support.mjs']) cpSync(join(root,'verification/portability/plans',name),join(directory,'src',name));
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
    const run=(args)=>spawnSync('gleam',args,{cwd:directory,encoding:'utf8',timeout:60000,maxBuffer:5*1024*1024,env:{...process.env,GIT_DIR:'',GIT_WORK_TREE:''}});
    const javascript=run(['test','--target','javascript']);
    assert.equal(javascript.status,0,javascript.stderr+'\n'+javascript.stdout);
    assert.match(javascript.stdout,/46 passed, no failures/);
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
    const currentRuntime=readFileSync(join(directory,'src/runtime.mjs'));
    // Old sources cannot compile migrated tests; a run also compiles test modules.
    rmSync(join(directory,'test'),{recursive:true});
    cpSync(join(root,'verification/portability/integration/baseline.gleam'),join(directory,'src/gargamelle.gleam'));
    cpSync(join(root,'verification/portability/integration/baseline-runtime.mjs'),join(directory,'src/runtime.mjs'));
    // Adapt only API names in copied callers; preserve the frozen baseline.
    const callers=['schema_fixtures.gleam','integration_probe.gleam','gargamelle/documentation.gleam'];
    const originals=callers.map(name=>[name,readFileSync(join(directory,'src',name),'utf8')]);
    for(const [name,source] of originals)writeFileSync(join(directory,'src',name),source.replaceAll('schema_string','emit_text').replaceAll('schema_json','emit_json').replaceAll('gargamelle.Json','gargamelle.Value').replaceAll('gargamelle.to_string','gargamelle.value_text').replaceAll('s.Strict','s.Closed').replaceAll(', s.Compact','').replaceAll(', gargamelle.Compact',''));
    assert.deepEqual(probe('javascript'),integrated,'schema bytes, decoded outputs or full DataError structures changed');
    for(const [name,source] of originals)writeFileSync(join(directory,'src',name),source);
    writeFileSync(join(directory,'src/gargamelle.gleam'),integratedSource);
    writeFileSync(join(directory,'src/runtime.mjs'),currentRuntime);
    cpSync(join(root,'test'),join(directory,'test'),{recursive:true});
    const ajv=new Ajv2020({strict:false,allErrors:true,ownProperties:true});
    for(const fixture of integrated) {
      const validate=ajv.compile(JSON.parse(fixture.schema));
      for(const entry of fixture.cases) {
        assert.equal(validate(JSON.parse(entry.input)),entry.accepted,fixture.name+': '+entry.input);
        assert.equal(entry.decoded!==null,entry.accepted);
      }
    }
    cpSync(join(root,'verification/portability/scalar_api.erl'),join(directory,'src/scalar_api.erl'));
    cpSync(join(root,'verification/portability/graph_api_test.gleam'),join(directory,'test/graph_api_test.gleam'));
    const build=spawnSync('make',['-C','priv/regex-src'],{cwd:directory,encoding:'utf8',timeout:60000});
    assert.equal(build.status,0,build.stdout+'\n'+build.stderr);
    const erlang=run(['test','--target','erlang']);
    assert.equal(erlang.status,0,erlang.stderr+'\n'+erlang.stdout);
    assert.match(erlang.stdout,/54 passed, no failures/);
    assert.deepEqual(probe('erlang'),integrated,'cross-target schema/output/diagnostic mismatch');
    benchmark('erlang');
    for(const [name,body,privateValue] of [
      ['decode','s.decode(self, value)',false],
      ['validate','s.validate(self, value)',false],
      ['emit','s.schema_string(self, s.Compact)',false],
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
    for (const [name, source, message] of [
      ['removed-value-type', 'import gargamelle as s\npub fn main(value: s.Value) { value }', /Unknown module type/],
      ['removed-policy-type', 'import gargamelle as s\npub fn main(policy: s.Policy) { policy }', /Unknown module type/],
      ['removed-closed', 'import gargamelle as s\npub fn main() { s.Closed }', /Unknown module value/],
      ['removed-value-text', 'import gargamelle as s\npub fn main() { s.value_text(Nil) }', /Unknown module value/],
      ['removed-emit-json', 'import gargamelle as s\npub fn main() { s.emit_json(s.text()) }', /Unknown module value/],
      ['removed-emit-text', 'import gargamelle as s\npub fn main() { s.emit_text(s.text()) }', /Unknown module value/],
      ['missing-json-format', 'import gargamelle as s\npub fn main() { let assert Ok(v) = s.parse("null") s.to_string(v) }', /Incorrect arity/],
      ['missing-schema-format', 'import gargamelle as s\npub fn main() { s.schema_string(s.text()) }', /Incorrect arity/],
      ['foreign-json', 'import gargamelle as s\nimport gleam/json\npub fn main() -> s.Json { json.string("not admitted") }', /Type mismatch/],
      ['opaque-json', 'import gargamelle as s\npub fn main() { s.Json("unadmitted") }', /Unknown module value/],
    ]) {
      writeFileSync(join(directory, 'src/negative.gleam'), source);
      for (const target of ['javascript', 'erlang']) {
        const result = run(['build', '--target', target]);
        assert.notEqual(result.status, 0, `${name} unexpectedly compiled on ${target}`);
        assert.match(result.stderr, message);
      }
    }
    t.diagnostic('32 compile-negative checks passed on the integrated API');
    t.diagnostic(`${integrated.length} schemas, ${integrated.reduce((sum,row)=>sum+row.cases.length,0)} independent cases; exact historical JavaScript and native comparison`);
    t.diagnostic('46 main-source tests and eight native process/graph tests passed');
  } finally {rmSync(directory,{recursive:true,force:true});}
});
