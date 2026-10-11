import test from 'node:test';
import assert from 'node:assert/strict';
import {cpSync,mkdtempSync,writeFileSync,mkdirSync,rmSync,existsSync,chmodSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {root,fingerprint} from '../evidence.mjs';

test('native shipment runs without checkout or build tools after explicit helper installation',(t)=>{
  const before=fingerprint(),directory=mkdtempSync(join(tmpdir(),'gargamelle-deployment-'));
  const library=join(directory,'library'),consumer=join(directory,'consumer'),deployed=join(directory,'deployed');
  const run=(command,args,cwd,success=true)=>{
    const r=spawnSync(command,args,{cwd,encoding:'utf8',timeout:60000,maxBuffer:5*1024*1024});
    assert.ifError(r.error);if(success)assert.equal(r.status,0,r.stdout+'\n'+r.stderr);else assert.notEqual(r.status,0);
    return r;
  };
  try {
    mkdirSync(library);mkdirSync(join(consumer,'src'),{recursive:true});
    for(const name of ['src','priv','gleam.toml','manifest.toml','build/packages'])cpSync(join(root,name),join(library,name),{recursive:true});
    for(const name of ['gleam_stdlib','gleam_json'])cpSync(join(root,'build/packages',name),join(directory,'vendor',name),{recursive:true});
    writeFileSync(join(consumer,'gleam.toml'),`name = "deployment_consumer"\nversion = "0.1.0"\ntarget = "erlang"\n[dependencies]\ngargamelle = { path = "../library" }\ngleam_stdlib = { path = "../vendor/gleam_stdlib" }\ngleam_json = { path = "../vendor/gleam_json" }\n`);
    cpSync(join(root,'verification/portability/deployment_consumer.gleam'),join(consumer,'src/deployment_consumer.gleam'));
    run('make',['-C','priv/regex-src'],library);
    run('gleam',['export','erlang-shipment'],consumer);
    cpSync(join(consumer,'build/erlang-shipment'),deployed,{recursive:true,dereference:true});
    const helper=join(deployed,'gargamelle','priv','gargamelle_regex_port');
    assert.equal(existsSync(helper),false,'Shipment unexpectedly includes a generated helper');
    cpSync(join(library,'build/native/gargamelle_regex_port'),join(directory,'helper-copy'));
    // Remove every build/source dependency before launching the deployed artifact.
    for(const path of [library,consumer,join(directory,'vendor')])rmSync(path,{recursive:true,force:true});
    const unrelated=join(directory,'unrelated');mkdirSync(unrelated);
    const entrypoint=join(deployed,'entrypoint.sh');
    const missing=run('sh',[entrypoint,'run'],unrelated,false);
    assert.match(missing.stdout+missing.stderr,/gargamelle_regex_failure|GargamelleRegexFailure/);
    assert.match(missing.stdout+missing.stderr,/enoent/i);
    cpSync(join(directory,'helper-copy'),helper);chmodSync(helper,0o755);
    assert.equal(run('sh',[entrypoint,'run'],unrelated).stdout.trim(),'native deployment passed');
    assert.equal(fingerprint().digest,before.digest,'Source changed during deployment test');
    mkdirSync(join(root,'reports'),{recursive:true});
    writeFileSync(join(root,'reports/native-deployment-evidence.json'),JSON.stringify({status:'passed',generatedAt:new Date().toISOString(),source:before,
      platform:process.platform,architecture:process.arch,otp:run('erl',['-noshell','-eval','io:format("~s", [erlang:system_info(otp_release)]), halt().'],unrelated).stdout.trim(),
      scope:'Local Gleam Erlang shipment; source checkouts and dependency sources removed; explicit helper installation; launch from unrelated working directory; missing helper fails operationally; not a Linux/Windows or all-release-tooling claim'},null,2)+'\n');
    t.diagnostic(`${process.platform} ${process.arch} shipment: explicit installed helper, no source/build fallback, Unicode/recursive/rendering consumer passed`);
  } finally {rmSync(directory,{recursive:true,force:true});}
});
