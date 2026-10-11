import test from 'node:test';
import assert from 'node:assert/strict';
import {cpSync,mkdtempSync,readFileSync,writeFileSync,mkdirSync,readdirSync,rmSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {root,fingerprint} from '../evidence.mjs';
import {compileOracle} from '../oracle.mjs';
import {compileSupplementary} from '../supplementary-oracle.mjs';
import {reference} from '../reference.mjs';
import {compileRecipes} from './generated-gleam.mjs';

test('six compiled native operator mutants fail independent behavioral checks',async(t)=>{
  const text={kind:'string'};
  const rows=[
    {recipe:{kind:'one',children:[text,{kind:'string',min:2}]},inputs:['"xx"','"x"','true']},
    {recipe:{kind:'record',open:false,fields:[{name:'field',presence:'optional',child:{kind:'nullable',child:text}}]},inputs:['{}','{"field":null}','{"field":"x"}']},
    {recipe:{kind:'record',open:false,fields:[{name:'field',presence:'required',child:text}]},inputs:['{"field":"x"}','{"field":"x","extra":true}']},
    {recipe:{kind:'string',min:1,max:2},inputs:['""','"x"','"xx"','"xxx"']},
    {recipe:{kind:'string',min:1,max:1},inputs:['"x"','"😀"','"xx"']},
    {recipe:{kind:'integer',min:-2,max:2},inputs:['-2','0','2','2.5']},
  ];
  const variants=[
    {name:'one-of-first-match',row:0,file:'gargamelle.erl',from:'case Exclusive andalso (Rest /= []) of',to:'case false andalso Exclusive andalso (Rest /= []) of'},
    {name:'present-null-as-absent',row:1,file:'gargamelle.erl',from:'gleam@option:map(member(V, Name), fun(Value) ->',to:'gleam@option:map(case member(V, Name) of {some, j_null} -> none; Found -> Found end, fun(Value) ->'},
    {name:'disabled-extra-key-rejection',row:2,file:'gargamelle.erl',from:'err(~"extra_key", path(P, erlang:element(1, X@2)))',to:'[]'},
    {name:'exclusive-inclusive-minimum',row:3,file:'gargamelle.erl',from:'N >= X;',to:'N > X;'},
    {name:'utf16-length-for-codepoints',row:4,file:'gargamelle_runtime.erl',from:'codepoints(Value) -> count_codepoints(Value, 0).',to:'codepoints(Value) -> byte_size(unicode:characters_to_binary(Value, utf8, {utf16, little})) div 2.'},
    {name:'incorrect-integer-conversion',row:5,file:'gargamelle_runtime.erl',from:'as_int(X) when is_float(X) -> trunc(X).',to:'as_int(X) when is_float(X) -> trunc(X) + 1.'},
  ];
  const before=fingerprint(),directory=mkdtempSync(join(tmpdir(),'gargamelle-native-operators-'));
  const run=(command,args)=>{
    const r=spawnSync(command,args,{cwd:directory,encoding:'utf8',timeout:60000,maxBuffer:5*1024*1024});
    assert.ifError(r.error);assert.equal(r.status,0,'Mutation must compile and execute, not fail through a crash:\n'+r.stderr+'\n'+r.stdout);return r.stdout;
  };
  let checkpoint={stage:'baseline'};
  try {
    for(const name of ['src','priv','build/packages','gleam.toml','manifest.toml'])cpSync(join(root,name),join(directory,name),{recursive:true});
    writeFileSync(join(directory,'src/generated_definitions.gleam'),compileRecipes(rows));
    cpSync(join(root,'verification/portability/generated_probe.gleam'),join(directory,'src/generated_probe.gleam'));
    run('make',['-C','priv/regex-src']);
    run('gleam',['run','--target','erlang','-m','generated_probe']);
    const build=join(directory,'build/dev/erlang'),ebin=join(build,'gargamelle/ebin');
    const paths=readdirSync(build).map(name=>join(build,name,'ebin'));
    const probe=()=>JSON.parse(run('erl',['-noshell','-pa',...paths,'-eval',"'gargamelle@@main':run(generated_probe)."]).trim());
    const normal=probe(),checks=[];
    for(const [index,row] of rows.entries()){
      const schema=JSON.parse(normal[index].schema),primary=compileOracle(schema),secondary=await compileSupplementary(schema);
      checks.push(result=>{
        assert.equal(result.index,index);assert.equal(result.cases.length,row.inputs.length);
        for(const [inputIndex,input] of row.inputs.entries()){
          const value=JSON.parse(input),expected=reference(row.recipe,value),actual=result.cases[inputIndex];
          assert.equal(primary(value).accepted,expected.accepted);assert.equal(secondary(value).accepted,expected.accepted);
          assert.equal(actual.input,input);assert.equal(actual.accepted,expected.accepted);
          if(expected.accepted)assert.deepEqual(actual.decoded,JSON.parse(JSON.stringify(expected.value)));
        }
      });
      checks[index](normal[index]);
    }
    const killed=[];
    for(const variant of variants){
      checkpoint={stage:'mutation',name:variant.name};
      const path=join(directory,'build/dev/erlang/gargamelle/_gleam_artefacts',variant.file);
      const source=readFileSync(path,'utf8');
      assert.equal(source.split(variant.from).length-1,1,variant.name+' requires one exact target');
      try {
        writeFileSync(path,source.replace(variant.from,variant.to));
        run('erlc',['-o',ebin,path]);
        const mutated=probe();assert.equal(mutated.length,normal.length);
        for(const [index,row] of mutated.entries())assert.equal(row.schema,normal[index].schema,variant.name+' must preserve emitted schema');
        assert.throws(()=>checks[variant.row](mutated[variant.row]),{name:'AssertionError'},variant.name+' survived independent checks');
        killed.push(variant.name);
      } finally {
        writeFileSync(path,source);run('erlc',['-o',ebin,path]);
      }
      // Restoration prevents a prior mutant from killing a later mutant.
      assert.deepEqual(probe(),normal,variant.name+' restoration failed');
    }
    assert.equal(fingerprint().digest,before.digest,'Production source changed during native mutation evidence');
    mkdirSync(join(root,'reports'),{recursive:true});
    writeFileSync(join(root,'reports/native-operator-mutations.json'),JSON.stringify({status:'passed',generatedAt:new Date().toISOString(),source:before,
      platform:process.platform,architecture:process.arch,mutants:killed,
      scope:'Six isolated compiled Erlang mutants; unchanged schemas; independent acceptance and JSON-normalized output checks; compile/crash failures do not count; restored baseline after each mutant'},null,2)+'\n');
    t.diagnostic('Six native operator mutants killed by acceptance/output assertions; schemas preserved; baseline restored after each mutation');
  } catch(error){
    mkdirSync(join(root,'reports'),{recursive:true});
    writeFileSync(join(root,'reports/native-operator-mutations-failure.json'),JSON.stringify({checkpoint,error:String(error)},null,2)+'\n');throw error;
  } finally {rmSync(directory,{recursive:true,force:true});}
});
