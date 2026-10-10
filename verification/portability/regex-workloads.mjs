// Opt-in bounded timing observations. Correctness checks have no timing threshold.
import assert from 'node:assert/strict';
import {cpSync,mkdtempSync,readFileSync,writeFileSync,mkdirSync,rmSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {root,fingerprint,sha256} from '../evidence.mjs';
const label=process.argv[2]??'current';
assert.match(label,/^[a-z0-9-]+$/);
const before=fingerprint();
const directory=mkdtempSync(join(tmpdir(),'gargamelle-regex-workload-'));
function run(command,args) {
  const r=spawnSync(command,args,{cwd:directory,encoding:'utf8',timeout:120000,maxBuffer:5*1024*1024});
  assert.ifError(r.error);assert.equal(r.status,0,r.stdout+'\n'+r.stderr);return r.stdout;
}
try {
  for(const name of ['src','priv','build/packages','gleam.toml','manifest.toml'])
    cpSync(join(root,name),join(directory,name),{recursive:true});
  // Retained af9acc5 binding: reproducible transport comparison, unchanged engine.
  if(label==='per-call') {
    assert.equal(sha256(readFileSync(join(root,'verification/portability/regex-per-call.erl'))),'c47f4a669b3b514ee2376e9aaf7afd69de205ab2fe46b56484aa49e74ee9f6e2','Retained af9acc5 binding changed');
    cpSync(join(root,'verification/portability/regex-per-call.erl'),join(directory,'src/gargamelle_regex.erl'));
    const runtime=join(directory,'src/gargamelle_runtime.erl');
    writeFileSync(runtime,readFileSync(runtime,'utf8').replace('gargamelle_regex:with_scope(fun() -> scoped(?WALK, #{}, Run) end)','scoped(?WALK, #{}, Run)'));
  }
  for(const name of ['plan_support.erl','plan_support.mjs'])
    cpSync(join(root,'verification/portability/plans',name),join(directory,'src',name));
  cpSync(join(root,'verification/portability/regex_workload.gleam'),join(directory,'src/regex_workload.gleam'));
  const rows=[];
  for(const count of [1,16,64]) for(const patterned of [false,true]) {
    const input=Array.from({length:count},(_,i)=>({id:`item_${i}`,url:`https://example.test/item/${i}`,time:'2026-10-10T12:34:56Z',title:'Greek α and emoji words'}));
    rows.push([`${patterned?'pattern':'plain'}-${count}`,patterned,count,true,JSON.stringify(input)]);
    if(patterned&&count===64) {
      input.at(-1).id='123 invalid';
      rows.push(['pattern-64-invalid-last',true,count,false,JSON.stringify(input)]);
    }
  }
  writeFileSync(join(directory,'src/regex_inputs.gleam'),`pub fn values() { [${rows.map(r=>`#(${r.map(v=>typeof v==='boolean'?v?'True':'False':JSON.stringify(v)).join(',')})`).join(',')}] }\n`);
  run('make',['-C','priv/regex-src']);
  const results={};
  for(const target of ['javascript','erlang']) results[target]=JSON.parse(run('gleam',['run','--target',target,'-m','regex_workload']).trim());
  assert.deepEqual(results.javascript.workloads.map(({name,patterned,records,accepted})=>({name,patterned,records,accepted})),results.erlang.workloads.map(({name,patterned,records,accepted})=>({name,patterned,records,accepted})));
  assert.equal(fingerprint().digest,before.digest,'Source changed during measurement');
  const report={source:before,generatedAt:new Date().toISOString(),node:process.version,unicode:process.versions.unicode,
    platform:process.platform,architecture:process.arch,gleam:run('gleam',['--version']).trim(),
    otp:run('erl',['-noshell','-eval','io:format("~s", [erlang:system_info(otp_release)]), halt().']).trim(),
    transport:label==='per-call'?'Retained af9acc5 per-call transport':'Current operation-scoped transport',
    scope:'Synthetic four-field provider-shaped records; one warmup and three samples; parsing excluded; no timing thresholds or application workload claim',results};
  mkdirSync(join(root,'reports'),{recursive:true});
  writeFileSync(join(root,`reports/regex-workloads-${label}.json`),JSON.stringify(report,null,2)+'\n');
  for(const [target,r] of Object.entries(results)) for(const row of r.workloads) {
    const median=values=>[...values].sort((a,b)=>a-b)[1];
    console.log(`${target} ${row.name}: decode ${median(row.decode_us)} us; validate ${median(row.validate_us)} us`);
  }
} finally {rmSync(directory,{recursive:true,force:true});}
