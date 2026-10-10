import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,cpSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../../',import.meta.url));

test('actual Erlang Gleam API preserves typed recursion and process-independent contexts',()=>{
  const directory=mkdtempSync(join(tmpdir(),'gargamelle-erlang-graph-'));
  try {
    for(const name of ['src','test','build/packages']) cpSync(join(root,name),join(directory,name),{recursive:true});
    for(const name of ['gleam.toml','manifest.toml']) cpSync(join(root,name),join(directory,name));
    cpSync(join(root,'verification/portability/scalar_api.erl'),join(directory,'src/scalar_api.erl'));
    cpSync(join(root,'verification/portability/graph_api_test.gleam'),join(directory,'test/graph_api_test.gleam'));
    const source=join(directory,'src/gargamelle.gleam');
    let text=readFileSync(source,'utf8');
    for(const name of ['pattern_valid','pattern_matches']) {
      const target=['codepoints','sorted'].includes(name)?'gargamelle_runtime':'scalar_api';
      const marker=`@external(javascript, "./runtime.mjs", "${name}")`;
      assert.equal(text.split(marker).length-1,1);
      text=text.replace(marker,`@external(erlang, "${target}", "${name}")\n${marker}`);
    }
    writeFileSync(source,text);
    const fixtures=join(directory,'src/schema_fixtures.gleam');
    writeFileSync(fixtures,readFileSync(fixtures,'utf8').replace(
      '@external(javascript, "./runtime.mjs", "int_text")',
      '@external(erlang, "gargamelle_runtime", "int_text")\n@external(javascript, "./runtime.mjs", "int_text")',
    ));
    const result=spawnSync('gleam',['test','--target','erlang'],{
      cwd:directory,encoding:'utf8',timeout:60000,maxBuffer:5*1024*1024,
      env:{...process.env,GIT_DIR:'',GIT_WORK_TREE:''},
    });
    assert.equal(result.status,0,result.stderr+'\n'+result.stdout);
    assert.match(result.stdout,/43 passed, no failures/);
  } finally {rmSync(directory,{recursive:true,force:true});}
});
