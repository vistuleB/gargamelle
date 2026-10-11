import test from 'node:test';
import assert from 'node:assert/strict';
import {cpSync,mkdtempSync,writeFileSync,mkdirSync,rmSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {root,fingerprint,sha256} from '../evidence.mjs';
import {corpus,seeds} from '../generated-corpus.mjs';
import {allKinds,childNodes} from '../recipe-model.mjs';
import {reference} from '../reference.mjs';
import {compileOracle,oracleOptions} from '../oracle.mjs';
import {compileSupplementary} from '../supplementary-oracle.mjs';
import {classifySplit} from '../oracle-classification.mjs';
import {compileRecipes} from './generated-gleam.mjs';

test('typed generated Erlang definitions agree with two independent schema oracles and recipe outputs',async(t)=>{
  const before=fingerprint(),rows=corpus(),directory=mkdtempSync(join(tmpdir(),'gargamelle-native-generated-'));
  const pairs=rows.reduce((n,row)=>n+row.inputs.length,0);
  assert.equal(pairs,17788);assert.equal(rows.length,886);
  const coverage={constructors:{},edges:{},rootOutcomes:{},expectedNestedOutcomes:{},depths:{},depth50:0,accepted:0,rejected:0,decoded:0,oracleSplits:{}};
  const observe=a=>{coverage.constructors[a.kind]=(coverage.constructors[a.kind]??0)+1;for(const c of childNodes(a)){const edge=a.kind+'>'+c.kind;coverage.edges[edge]=(coverage.edges[edge]??0)+1;observe(c);}};
  const run=(command,args)=>{
    const r=spawnSync(command,args,{cwd:directory,encoding:'utf8',timeout:180000,maxBuffer:80*1024*1024});
    if(r.error||r.status!==0) {
      const marker=[...r.stderr.matchAll(/^GARGAMELLE_CASE (.+)$/gm)].at(-1);
      if(marker) {
        const progress=JSON.parse(marker[1]),row=rows[progress.index];
        checkpoint={...checkpoint,progress,context:row.context,recipe:row.recipe,input:row.inputs[progress.inputIndex]};
      }
      checkpoint={...checkpoint,stderr:r.stderr.slice(-5000)};
    }
    assert.ifError(r.error);assert.equal(r.status,0,r.stderr.slice(-5000)+'\n'+r.stdout.slice(-1000));return r.stdout;
  };
  let checkpoint={stage:'compile',source:before.digest};
  try {
    for(const name of ['src','priv','build/packages','gleam.toml','manifest.toml'])cpSync(join(root,name),join(directory,name),{recursive:true});
    writeFileSync(join(directory,'src/generated_definitions.gleam'),compileRecipes(rows));
    cpSync(join(root,'verification/portability/generated_probe.gleam'),join(directory,'src/generated_probe.gleam'));
    run('make',['-C','priv/regex-src']);
    const rootBuild=spawnSync('gleam',['build','--target','javascript'],{cwd:root,encoding:'utf8',timeout:60000});
    assert.ifError(rootBuild.error);assert.equal(rootBuild.status,0,rootBuild.stderr);
    const {build,s}=await import('../generated-api.mjs');
    const results={};
    for(const target of ['javascript','erlang']) {
      checkpoint={stage:'execution',target,source:before.digest};
      results[target]=JSON.parse(run('gleam',['run','--target',target,'-m','generated_probe']).trim());
      assert.equal(results[target].length,rows.length);
    }
    // JSON-normalized fixture outputs; numeric sign/representation has separate gates.
    const normalize=value=>JSON.parse(JSON.stringify(value));
    for(let i=0;i<rows.length;i++) {
      const {recipe,inputs,context}=rows[i],native=results.erlang[i],javascript=results.javascript[i];
      checkpoint={stage:'oracle',index:i,context,recipe,native,javascript};
      observe(recipe);
      if(context.depth!=null)coverage.depths[context.depth]=(coverage.depths[context.depth]??0)+1;
      if(context.seed==='depth50')coverage.depth50++;
      assert.equal(native.index,i);assert.equal(native.cases.length,inputs.length);
      assert.deepEqual(normalize(native),normalize(javascript),'Native schema/output/full diagnostics differ from typed JavaScript');
      assert.equal(native.schema,s.schema_string(build(recipe)),'Typed recipe compiler changed the JavaScript recipe schema');
      const schema=JSON.parse(native.schema),ajv=compileOracle(schema),hyperjump=await compileSupplementary(schema);
      for(let j=0;j<inputs.length;j++) {
        const entry=native.cases[j],value=JSON.parse(inputs[j]);
        checkpoint={stage:'case',index:i,inputIndex:j,context,recipe,input:inputs[j],schema,entry};
        assert.equal(entry.input,inputs[j]);
        const primary=ajv(value),secondary=hyperjump(value),expected=reference(recipe,value,(path,kind,accepted)=>{
          if(path!=='$'){const key=kind+':'+accepted;coverage.expectedNestedOutcomes[key]=(coverage.expectedNestedOutcomes[key]??0)+1;}
        });
        const outcome=recipe.kind+':'+entry.accepted;
        coverage.rootOutcomes[outcome]=(coverage.rootOutcomes[outcome]??0)+1;
        const split=classifySplit(schema,value,primary,secondary);
        if(split)coverage.oracleSplits[split]=(coverage.oracleSplits[split]??0)+1;
        assert.equal(expected.accepted,secondary.accepted,'Independent recipe acceptance disagrees with Hyperjump');
        assert.equal(entry.accepted,secondary.accepted,'Native acceptance disagrees with independent schema oracle');
        if(entry.accepted) {
          assert.deepEqual(normalize(entry.decoded),normalize(expected.value),'Native decoded output differs from independent recipe interpreter');
          assert.deepEqual(entry.errors,[]);coverage.accepted++;coverage.decoded++;
        } else {assert.ok(entry.errors.length>0);coverage.rejected++;}
      }
    }
    for(const kind of allKinds) {
      assert.ok(coverage.constructors[kind],kind);
      for(const accepted of [true,false]){
        assert.ok(coverage.rootOutcomes[kind+':'+accepted],kind+' root '+accepted);
        assert.ok(coverage.expectedNestedOutcomes[kind+':'+accepted],kind+' nested proposal '+accepted);
      }
    }
    for(let depth=0;depth<=6;depth++)assert.ok(coverage.depths[depth]);
    assert.equal(coverage.depth50,14);
    assert.equal(coverage.accepted+coverage.rejected,pairs);
    assert.equal(fingerprint().digest,before.digest,'Source changed during native evidence');
    const report={status:'passed',contractRevision:5,generatedAt:new Date().toISOString(),source:before,
      corpusSha256:sha256(JSON.stringify(rows)),schemas:rows.length,pairs,seeds,coverage,oracleOptions,
      node:process.version,unicode:process.versions.unicode,gleam:run('gleam',['--version']).trim(),
      otp:run('erl',['-noshell','-eval','io:format("~s", [erlang:system_info(otp_release)]), halt().']).trim(),
      platform:process.platform,architecture:process.arch,
      scope:'Actual Erlang definitions constructed by typed public Gleam APIs; emitted schemas checked by Ajv and Hyperjump; JSON-normalized decoded outputs checked by independent recipe interpreter; exact typed cross-target schema and full diagnostic comparison; no native decoder substitution',
      limits:{subprocessTimeoutMs:180000,maxOutputBytes:80*1024*1024},excluded:['All official schema-suite cases','Complete native mutation coverage','Linux/Windows and other OTP versions','Exhaustive parser/regex conformance','Publication approval']};
    mkdirSync(join(root,'reports'),{recursive:true});writeFileSync(join(root,'reports/native-generated-evidence.json'),JSON.stringify(report,null,2)+'\n');
    t.diagnostic(`${rows.length} typed schemas; ${pairs} native pairs; ${coverage.decoded} independent decoded-output comparisons; ${Object.keys(coverage.edges).length} parent/child edges`);
  } catch(error) {
    mkdirSync(join(root,'reports'),{recursive:true});
    writeFileSync(join(root,'reports/native-generated-failure.json'),JSON.stringify({checkpoint,error:{name:error.name,message:error.message,stack:error.stack}},null,2)+'\n');
    writeFileSync(join(root,'reports/native-generated-failing-corpus.json'),JSON.stringify(rows,null,2)+'\n');
    writeFileSync(join(root,'reports/native-generated-failing-source.gleam'),compileRecipes(rows));
    throw error;
  } finally {rmSync(directory,{recursive:true,force:true});}
});
