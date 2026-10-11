import test from 'node:test';
import assert from 'node:assert/strict';
import {cpSync,mkdtempSync,readFileSync,writeFileSync,mkdirSync,rmSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {root,fingerprint,sha256} from '../evidence.mjs';
import {translate} from '../official/translate.mjs';
import {compileOracle} from '../oracle.mjs';
import {compileSupplementary} from '../supplementary-oracle.mjs';
import {reference} from '../reference.mjs';
import {compileRecipes} from './generated-gleam.mjs';

test('actual Erlang API passes every unchanged selected official schema case',async(t)=>{
  const before=fingerprint(),base=join(root,'verification/official');
  const provenance=JSON.parse(readFileSync(join(base,'provenance.json')));
  const selection=JSON.parse(readFileSync(join(base,'selection.json')));
  assert.equal(provenance.commit,selection.commit);
  const inventory=new Map(selection.groups.map(row=>[row.id,row]));
  let groups=0;
  for(const file of provenance.files){
    const bytes=readFileSync(join(base,file.path));assert.equal(sha256(bytes),file.sha256,file.path);
    for(const [index,group] of JSON.parse(bytes).entries()){
      const row=inventory.get(`${file.path}#${index}`);assert.ok(row);assert.equal(row.tests,group.tests.length);
      if(row.status==='selected')assert.deepEqual(row.recipe,JSON.parse(JSON.stringify(translate(group.schema))));
      else {assert.equal(row.status,'excluded');assert.ok(row.reason);assert.throws(()=>translate(group.schema),error=>error.message===row.reason);}
      groups++;
    }
  }
  assert.equal(groups,inventory.size);assert.equal(groups,selection.groups.length);
  const rows=selection.groups.filter(row=>row.status==='selected').map(row=>{
    const [path,index]=row.id.split('#'),group=JSON.parse(readFileSync(join(base,path)))[Number(index)];
    return {recipe:row.recipe,inputs:group.tests.map(fixture=>JSON.stringify(fixture.data)),context:{id:row.id},group};
  });
  assert.equal(rows.length,27);assert.equal(rows.reduce((sum,row)=>sum+row.inputs.length,0),109);
  const directory=mkdtempSync(join(tmpdir(),'gargamelle-native-official-'));
  let checkpoint={stage:'build'};
  const run=(command,args)=>{
    const r=spawnSync(command,args,{cwd:directory,encoding:'utf8',timeout:120000,maxBuffer:8*1024*1024});
    assert.ifError(r.error);assert.equal(r.status,0,r.stderr.slice(-5000)+'\n'+r.stdout.slice(-1000));return r.stdout;
  };
  try {
    for(const name of ['src','priv','build/packages','gleam.toml','manifest.toml'])cpSync(join(root,name),join(directory,name),{recursive:true});
    writeFileSync(join(directory,'src/generated_definitions.gleam'),compileRecipes(rows));
    cpSync(join(root,'verification/portability/generated_probe.gleam'),join(directory,'src/generated_probe.gleam'));
    run('make',['-C','priv/regex-src']);
    const results={};
    for(const target of ['javascript','erlang']){
      checkpoint={stage:'execution',target};
      results[target]=JSON.parse(run('gleam',['run','--target',target,'-m','generated_probe']).trim());
      assert.equal(results[target].length,rows.length);
    }
    let accepted=0,rejected=0;
    for(const [index,row] of rows.entries()){
      const native=results.erlang[index];checkpoint={stage:'oracle',id:row.context.id};
      assert.equal(native.index,index);assert.equal(native.cases.length,row.group.tests.length);
      assert.deepEqual(native,results.javascript[index],'Typed cross-target schemas, outputs or full diagnostics differ');
      const emitted=JSON.parse(native.schema),original={...row.group.schema,$schema:'https://json-schema.org/draft/2020-12/schema'};
      const checks=[compileOracle(original),await compileSupplementary(original),compileOracle(emitted),await compileSupplementary(emitted)];
      for(const [inputIndex,fixture] of row.group.tests.entries()){
        checkpoint={id:row.context.id,inputIndex,description:fixture.description,input:row.inputs[inputIndex],expected:fixture.valid};
        for(const check of checks)assert.equal(check(fixture.data).accepted,fixture.valid,fixture.description);
        const actual=native.cases[inputIndex],expected=reference(row.recipe,fixture.data);
        assert.equal(actual.input,row.inputs[inputIndex]);assert.equal(actual.accepted,fixture.valid,fixture.description);
        assert.equal(expected.accepted,fixture.valid);
        if(fixture.valid){assert.deepEqual(actual.decoded,JSON.parse(JSON.stringify(expected.value)));assert.deepEqual(actual.errors,[]);accepted++;}
        else {assert.ok(actual.errors.length>0);rejected++;}
      }
    }
    assert.equal(fingerprint().digest,before.digest,'Source changed during official native evidence');
    mkdirSync(join(root,'reports'),{recursive:true});
    writeFileSync(join(root,'reports/native-official-evidence.json'),JSON.stringify({status:'passed',generatedAt:new Date().toISOString(),source:before,
      suiteCommit:selection.commit,selectionSha256:sha256(readFileSync(join(base,'selection.json'))),groups:rows.length,cases:accepted+rejected,accepted,rejected,
      platform:process.platform,architecture:process.arch,node:process.version,gleam:run('gleam',['--version']).trim(),otp:run('erl',['-noshell','-eval','io:format("~s", [erlang:system_info(otp_release)]), halt().']).trim(),
      scope:'All 109 currently selected official cases, unchanged inputs and validity expectations; original and emitted schemas checked with Ajv and Hyperjump; typed real library on both targets',
      excluded:['357 explicitly excluded official groups','Optional suite collections','Full dialect conformance','Exhaustive parser/regex conformance']},null,2)+'\n');
    t.diagnostic(`27 official groups; 109 cases (${accepted} accepted, ${rejected} rejected); both compiled targets and both independent validators`);
  } catch(error){
    mkdirSync(join(root,'reports'),{recursive:true});
    writeFileSync(join(root,'reports/native-official-failure.json'),JSON.stringify({checkpoint,error:String(error)},null,2)+'\n');throw error;
  } finally {rmSync(directory,{recursive:true,force:true});}
});
