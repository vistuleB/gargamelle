import assert from 'node:assert/strict';
import {cpSync,existsSync,mkdirSync,mkdtempSync,readFileSync,readdirSync,rmSync,writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {root,fingerprint,sha256} from './evidence.mjs';

// Local preparation only: no registry lookup, tag, push or publication.
const reports=join(root,'reports');mkdirSync(reports,{recursive:true});
const before=fingerprint(),commands=[],logs={};
const reportPath=join(reports,'release-preparation.json');
const run=(command,args,cwd=root,label)=>{
  commands.push({command,args});
  const result=spawnSync(command,args,{cwd,encoding:'utf8',timeout:240000,maxBuffer:40*1024*1024});
  const output=(result.stdout??'')+(result.stderr??'');
  if(label){writeFileSync(join(reports,label),output);logs[label]=sha256(output);}
  assert.ifError(result.error);assert.equal(result.status,0,`${command} failed: ${output.slice(-6000)}`);
  return result.stdout;
};
let directory;
writeFileSync(reportPath,JSON.stringify({status:'running',source:before.digest})+'\n');
try {
  const version=readFileSync(join(root,'gleam.toml'),'utf8').match(/^version = "([^"]+)"$/m)[1];
  assert.equal(version,'0.2.0');
  const pkg=JSON.parse(readFileSync(join(root,'package.json'))),lock=JSON.parse(readFileSync(join(root,'package-lock.json')));
  assert.equal(pkg.version,version);assert.equal(lock.version,version);assert.equal(lock.packages[''].version,version);
  assert.equal(pkg.private,true);
  console.log('Checking JavaScript evidence…');
  run('npm',['run','verify'],root,'release-javascript.log');
  run('npm',['run','check:release'],root,'release-review.log');
  console.log('Checking native evidence…');
  const native=run('npm',['run','verify:erlang-primitives'],root,'release-native.log');
  const count=name=>Number(native.match(new RegExp(`^[#ℹ] ${name} (\\d+)$`,'m'))?.[1]);
  assert.equal(count('tests'),16);assert.equal(count('pass'),16);
  for(const name of ['fail','cancelled','skipped','todo'])assert.equal(count(name),0);
  const js=JSON.parse(readFileSync(join(root,'reports/evidence.json')));
  const generated=JSON.parse(readFileSync(join(root,'reports/native-generated-evidence.json')));
  assert.equal(js.coverage.corpusSha256,generated.corpusSha256);
  assert.equal(generated.source.digest,before.digest);
  const official=JSON.parse(readFileSync(join(root,'reports/native-official-evidence.json')));
  assert.equal(official.status,'passed');assert.equal(official.source.digest,before.digest);assert.equal(official.cases,109);
  run('gleam',['docs','build'],root,'release-docs.log');
  run('gleam',['export','hex-tarball'],root,'release-export.log');

  directory=mkdtempSync(join(tmpdir(),'gargamelle-release-'));
  const outer=join(directory,'outer'),library=join(directory,'library'),consumer=join(directory,'consumer');
  mkdirSync(outer);mkdirSync(library);mkdirSync(join(consumer,'src'),{recursive:true});
  const archive=join(root,'build',`gargamelle-${version}.tar`);
  run('tar',['-xf',archive,'-C',outer]);
  const contents=join(outer,'contents.tar.gz');
  const entries=run('tar',['-tzf',contents]).trim().split('\n').map(path=>path.replace(/^\.\//,''));
  for(const path of entries){
    assert.ok(!path.startsWith('/')&&!path.split('/').includes('..'),`Unsafe archive path: ${path}`);
    assert.ok(!/(^|\/)(?:build|node_modules|reports|\.git|\.aws)(?:\/|$)|\.(?:beam|o|dylib|so|exe)$|(^|\/)gargamelle_regex_port$/.test(path),`Generated/private artifact: ${path}`);
    assert.ok(!/(^|\/)\.env(?:\.|$)|(?:^|\/)(?:credentials|id_rsa|id_ed25519)$/.test(path),`Credential path: ${path}`);
  }
  for(const path of ['gleam.toml','README.md','LICENSE','src/gargamelle.gleam','src/runtime.mjs','src/gargamelle_runtime.erl','src/gargamelle_regex.erl','priv/regex-src/Makefile','priv/regex-src/PROVENANCE.json','priv/regex-src/LICENSE.quickjs'])assert.ok(entries.includes(path),`Missing archive member: ${path}`);
  run('tar',['-xzf',contents,'-C',library]);
  // Consumers use only the extracted package and pinned dependency source copies.
  for(const name of ['gleam_stdlib','gleam_json'])cpSync(join(root,'build/packages',name),join(directory,'vendor',name),{recursive:true});
  writeFileSync(join(consumer,'gleam.toml'),`name = "release_consumer"\nversion = "0.1.0"\n[dependencies]\ngargamelle = { path = "../library" }\ngleam_stdlib = { path = "../vendor/gleam_stdlib" }\ngleam_json = { path = "../vendor/gleam_json" }\n`);
  const fixture=readFileSync(join(root,'verification/portability/deployment_consumer.gleam'),'utf8').replace('native deployment passed','release consumer passed');
  writeFileSync(join(consumer,'src/release_consumer.gleam'),fixture);
  console.log('Checking fresh consumers of the exported archive…');
  for(const target of ['javascript','erlang']){
    if(target==='erlang')run('make',['-C','priv/regex-src'],library,'release-consumer-helper.log');
    const output=run('gleam',['run','--target',target],consumer,`release-consumer-${target}.log`);
    assert.equal(output.trim(),'release consumer passed');
  }
  const provenance=JSON.parse(readFileSync(join(library,'priv/regex-src/PROVENANCE.json')));
  for(const [name,record] of Object.entries(provenance.files))assert.equal(sha256(readFileSync(join(library,'priv/regex-src',name))),record.vendoredSha256,name);
  assert.equal(existsSync(join(library,'node_modules')),false);
  const modules=readdirSync(join(root,'build/dev/docs/gargamelle')).filter(name=>name.endsWith('.html'));
  assert.ok(modules.includes('gargamelle.html'));assert.ok(!modules.includes('schema_fixtures.html'));
  assert.equal(fingerprint().digest,before.digest,'Source changed during release preparation');
  const report={status:'prepared',version,generatedAt:new Date().toISOString(),source:before,
    platform:process.platform,architecture:process.arch,commands,logs,
    versions:{node:process.version,unicode:process.versions.unicode,gleam:run('gleam',['--version']).trim(),otp:run('erl',['-noshell','-eval','io:format("~s", [erlang:system_info(otp_release)]), halt().']).trim(),beam:run('erl',['-noshell','-eval','io:format("~s", [erlang:system_info(system_version)]), halt().']).trim()},
    archive:{path:`build/gargamelle-${version}.tar`,sha256:sha256(readFileSync(archive)),contentsSha256:sha256(readFileSync(contents)),members:entries},
    counts:{javascript:js.counts,nativeGroups:16,nativeOfficialCases:official.cases,nativeGeneratedPairs:generated.pairs,nativeDecodedOutputs:generated.coverage.decoded},
    support:{javascript:process.version,nativeEvidence:`${process.platform} ${process.arch} / OTP ${official.otp} / explicit C helper installation`,unqualified:['Platforms and OTP versions outside this recorded run','Other deployment tooling'],unsupported:['Windows native helper','Browsers/Bun/Deno']},
    reviewRequired:['V08 preservation argument','Declared Erlang support scope and remaining platform qualification'],
    scope:'Prepared local candidate; not publication approval or broad Erlang support qualification'};
  writeFileSync(reportPath,JSON.stringify(report,null,2)+'\n');
  console.log(`PREPARED: ${version}; both target gates, docs, archive inspection and fresh consumers passed. Publication and broad Erlang qualification remain separate.`);
} catch(error){
  writeFileSync(reportPath,JSON.stringify({status:'failed',source:before.digest,error:String(error),logs},null,2)+'\n');
  throw error;
} finally {if(directory)rmSync(directory,{recursive:true,force:true});}
