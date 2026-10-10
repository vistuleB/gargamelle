import test from 'node:test';
import assert from 'node:assert/strict';
import {cpSync,mkdtempSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {root} from '../evidence.mjs';
import {compileOracle} from '../oracle.mjs';
import {compileSupplementary} from '../supplementary-oracle.mjs';
import {compileRecipes} from './generated-gleam.mjs';

test('generated native oracle detects a regex adapter that always reports a match',async(t)=>{
  const text={kind:'string'},pattern={kind:'string',patterns:['^yes$']};
  const rows=[
    {recipe:pattern,inputs:['"yes"','"no"']},
    {recipe:{kind:'exclude',child:text,forbidden:pattern},inputs:['"yes"','"no"']},
    {recipe:{kind:'conditional',child:text,condition:pattern,consequence:{kind:'constant',value:'yes'},alternative:{kind:'constant',value:'no'}},inputs:['"yes"','"no"']},
    {recipe:{kind:'contains',child:text,matching:pattern,minimum:1,maximum:1},inputs:['["yes"]','["no"]']},
    {recipe:{kind:'property_names',child:text,keys:pattern},inputs:['{"yes":"x"}','{"no":"x"}']},
  ];
  const directory=mkdtempSync(join(tmpdir(),'gargamelle-native-mutation-'));
  const run=(command,args)=>{
    const r=spawnSync(command,args,{cwd:directory,encoding:'utf8',timeout:60000,maxBuffer:5*1024*1024});
    assert.ifError(r.error);assert.equal(r.status,0,r.stderr.slice(-5000)+'\n'+r.stdout);return r.stdout;
  };
  try {
    for(const name of ['src','priv','build/packages','gleam.toml','manifest.toml'])cpSync(join(root,name),join(directory,name),{recursive:true});
    cpSync(join(root,'verification/portability/generated_probe.gleam'),join(directory,'src/generated_probe.gleam'));
    writeFileSync(join(directory,'src/generated_definitions.gleam'),compileRecipes(rows));
    run('make',['-C','priv/regex-src']);
    const probe=()=>JSON.parse(run('gleam',['run','--target','erlang','-m','generated_probe']).trim());
    const normal=probe();
    const adapter=join(directory,'src/gargamelle_regex.erl'),source=readFileSync(adapter,'utf8');
    const marker='pattern_matches(Pattern, Text) -> request(1, Pattern, Text).';
    assert.equal(source.split(marker).length-1,1);
    writeFileSync(adapter,source.replace(marker,'pattern_matches(_, _) -> true.'));
    const mutant=probe();
    for(let i=0;i<rows.length;i++) {
      assert.equal(mutant[i].schema,normal[i].schema,'Mutation changed schema rather than native acceptance');
      const schema=JSON.parse(normal[i].schema),primary=compileOracle(schema),secondary=await compileSupplementary(schema);
      const expected=rows[i].inputs.map(input=>{
        const value=JSON.parse(input),first=primary(value).accepted,second=secondary(value).accepted;
        assert.equal(first,second);return second;
      });
      assert.deepEqual(normal[i].cases.map(entry=>entry.accepted),expected);
      assert.notDeepEqual(mutant[i].cases.map(entry=>entry.accepted),expected,rows[i].recipe.kind+' failed to detect native mutation');
    }
    t.diagnostic('One native adapter mutant detected through string, exclusion, conditional, contains and property-name paths');
  } finally {rmSync(directory,{recursive:true,force:true});}
});
