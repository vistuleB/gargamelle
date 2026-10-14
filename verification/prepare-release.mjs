import assert from 'node:assert/strict';
import {cpSync,existsSync,mkdirSync,mkdtempSync,readFileSync,readdirSync,rmSync,writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {root,fingerprint,sha256} from './evidence.mjs';
import {checkPackageReadme} from './package-documentation.mjs';

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
  assert.equal(version,'0.9.0');
  const pkg=JSON.parse(readFileSync(join(root,'package.json'))),lock=JSON.parse(readFileSync(join(root,'package-lock.json')));
  assert.equal(pkg.version,version);assert.equal(lock.version,version);assert.equal(lock.packages[''].version,version);
  assert.equal(pkg.private,true);
  console.log('Checking JavaScript evidence…');
  run('npm',['run','verify'],root,'release-javascript.log');
  run('npm',['run','check:release'],root,'release-review.log');
  console.log('Checking native evidence…');
  const native=run('npm',['run','verify:erlang-primitives'],root,'release-native.log');
  const count=name=>Number(native.match(new RegExp(`^[#ℹ] ${name} (\\d+)$`,'m'))?.[1]);
  assert.equal(count('tests'),17);assert.equal(count('pass'),17);
  for(const name of ['fail','cancelled','skipped','todo'])assert.equal(count(name),0);
  const js=JSON.parse(readFileSync(join(root,'reports/evidence.json')));
  const generated=JSON.parse(readFileSync(join(root,'reports/native-generated-evidence.json')));
  assert.equal(js.coverage.corpusSha256,generated.corpusSha256);
  assert.equal(generated.source.digest,before.digest);
  const official=JSON.parse(readFileSync(join(root,'reports/native-official-evidence.json')));
  assert.equal(official.status,'passed');assert.equal(official.source.digest,before.digest);assert.equal(official.cases,109);
  const mutations=JSON.parse(readFileSync(join(root,'reports/native-operator-mutations.json')));
  assert.equal(mutations.status,'passed');assert.equal(mutations.source.digest,before.digest);assert.equal(mutations.mutants.length,6);
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
  for(const path of ['gleam.toml','README.md','LICENSE','src/gargamelle.gleam','src/gargamelle/encoding.gleam','src/gargamelle/boundary.gleam','src/gargamelle/diagnostics.gleam','src/gargamelle/encoding_runtime.mjs','src/gargamelle_encoding_runtime.erl','src/runtime.mjs','src/gargamelle_runtime.erl','src/gargamelle_regex.erl','priv/regex-src/Makefile','priv/regex-src/PROVENANCE.json','priv/regex-src/LICENSE.quickjs'])assert.ok(entries.includes(path),`Missing archive member: ${path}`);
  assert.ok(!entries.includes('src/schema_fixtures.gleam'),'Verification fixtures must not ship');
  assert.ok(!entries.some(path=>path.startsWith('test/')),'Test modules must not ship');
  assert.ok(!entries.some(path=>path.startsWith('verification/experiments/')),'Private experiments must not ship');
  const topLevel=entries.flatMap(path=>/^src\/([^/]+)\.gleam$/.exec(path)?.slice(1)??[]);
  assert.deepEqual(topLevel,['gargamelle'],'Package must expose only its own top-level namespace');
  run('tar',['-xzf',contents,'-C',library]);
  checkPackageReadme(readFileSync(join(root,'README.md')),readFileSync(join(library,'README.md')));
  // Consumers use only the extracted package and pinned dependency source copies.
  for(const name of ['gleam_stdlib','gleam_json'])cpSync(join(root,'build/packages',name),join(directory,'vendor',name),{recursive:true});
  writeFileSync(join(consumer,'gleam.toml'),`name = "release_consumer"\nversion = "0.1.0"\n[dependencies]\ngargamelle = { path = "../library" }\ngleam_stdlib = { path = "../vendor/gleam_stdlib" }\ngleam_json = { path = "../vendor/gleam_json" }\n`);
  const fixture=readFileSync(join(root,'verification/portability/deployment_consumer.gleam'),'utf8').replace('native deployment passed','release consumer passed');
  writeFileSync(join(consumer,'src/release_consumer.gleam'),fixture);
  cpSync(join(root,'verification/contract_consumer.gleam'),join(consumer,'src/contract_consumer.gleam'));
  // Compile the actual public snippets rather than hand-maintained copies.
  const readme=readFileSync(join(root,'README.md'),'utf8');
  const snippets=[...readme.matchAll(/```gleam\n([\s\S]*?)\n```/g)].map(match=>match[1]);
  assert.equal(snippets.length,3);
  writeFileSync(join(consumer,'src/readme_names.gleam'),snippets[0]);
  const expectedNames = readme.match(/Output:\n\n```text\n([\s\S]*?)\n```/)[1];
  writeFileSync(join(consumer,'src/readme_boundaries.gleam'),snippets[1]);
  const expectedBoundaries = readme.split('## Receiving boundaries')[1].match(/Output:\n\n```text\n([\s\S]*?)\n```/)[1];
  writeFileSync(join(consumer,'src/readme_user.gleam'),snippets[2]+`
import gleam/io
pub fn main() {
  let assert Ok(User("Brainy", True)) = read_user("{\\\"name\\\":\\\"Brainy\\\",\\\"active\\\":true}")
  io.println("README user passed")
}
`);
  const advanced=readFileSync(join(root,'docs/advanced.md'),'utf8');
  const recipe=advanced.split('## Optional HTML documentation')[1].match(/```gleam\n([\s\S]*?)\n```/)[1];
  writeFileSync(join(consumer,'src/preferences_reference.gleam'),recipe);
  const expectedArticle=readFileSync(join(root,'documentation/example.html'),'utf8').match(/<article[\s\S]*?<\/article>/)[0];
  const encodingGuide=readFileSync(join(root,'docs/encoding.md'),'utf8');
  const encodingSnippets=[...encodingGuide.matchAll(/```gleam\n([\s\S]*?)\n```/g)].map(match=>match[1]);
  const encodingOutputs=[...encodingGuide.matchAll(/```text\n([\s\S]*?)\n```/g)].map(match=>match[1]);
  assert.equal(encodingSnippets.length,2);assert.equal(encodingOutputs.length,2);
  const encodingConsumers=encodingSnippets.map((source,index)=>{
    const module=`encoding_guide_${index}`;
    writeFileSync(join(consumer,`src/${module}.gleam`),source);
    return [module,encodingOutputs[index]];
  });
  const jsonGuide=readFileSync(join(root,'docs/json-values.md'),'utf8');
  const jsonSnippets=[...jsonGuide.matchAll(/```gleam\n([\s\S]*?)\n```/g)].map(match=>match[1]);
  const jsonOutputs=[...jsonGuide.matchAll(/```text\n([\s\S]*?)\n```/g)].map(match=>match[1]);
  assert.equal(jsonSnippets.length,2);assert.equal(jsonOutputs.length,2);
  const jsonConsumers=jsonSnippets.map((source,index)=>{
    const module=`json_guide_${index}`;
    writeFileSync(join(consumer,`src/${module}.gleam`),source);
    return [module,jsonOutputs[index]];
  });
  cpSync(join(root,'verification/json_consumer.gleam'),join(consumer,'src/json_consumer.gleam'));
  cpSync(join(root,'test/modifier_fixture.gleam'),join(consumer,'src/modifier_fixture.gleam'));
  // New public modules must also work when installed from the exported archive.
  const diagnosticGuide=readFileSync(join(root,'docs/diagnostics.md'),'utf8');
  const diagnosticSource=diagnosticGuide.match(/```gleam\n([\s\S]*?)\n```/)[1];
  const diagnosticOutput=diagnosticGuide.match(/```text\n([\s\S]*?)\n```/)[1];
  writeFileSync(join(consumer,'src/diagnostics_consumer.gleam'),diagnosticSource);
  for(const name of ['provider_roundtrip.gleam','paired_boundary_example.gleam'])
    cpSync(join(root,'test',name),join(consumer,'src',name));
  const providerOutput='{"answers":[true,false],"score":1}\nLoad rejected: score does not match answers\nSave rejected: score does not match answers';
  const pairedGuide=readFileSync(join(root,'docs/boundaries.md'),'utf8').split('## Paired loading and saving')[1];
  const pairedSource=pairedGuide.match(/```gleam\n([\s\S]*?)\n```/)[1];
  writeFileSync(join(consumer,'src/paired_guide.gleam'),pairedSource);
  const pairedOutput=pairedGuide.match(/```text\n([\s\S]*?)\n```/)[1];
  const boundaryConsumers=[['diagnostics_consumer',diagnosticOutput],['provider_roundtrip',providerOutput],['paired_boundary_example','{"answers":[true,false],"score":1}\nSave rejected: score does not match answers'],['paired_guide',pairedOutput]];
  const modifierObservations=[];
  console.log('Checking fresh consumers of the exported archive…');
  for(const target of ['javascript','erlang']){
    if(target==='erlang')run('make',['-C','priv/regex-src'],library,'release-consumer-helper.log');
    const output=run('gleam',['run','--target',target],consumer,`release-consumer-${target}.log`);
    assert.equal(output.trim(),'release consumer passed');
    for(const [module,expected] of [['contract_consumer','release contract consumer passed'],['readme_names',expectedNames],['readme_boundaries',expectedBoundaries],['readme_user','README user passed'],['preferences_reference',expectedArticle],...encodingConsumers,...jsonConsumers,...boundaryConsumers,['json_consumer','release JSON consumer passed']]){
      const result=run('gleam',['run','--target',target,'--module',module],consumer,`release-${module}-${target}.log`);
      assert.equal(result.trim(),expected,`${module} output differs on ${target}`);
    }
    const modifiers=JSON.parse(run('gleam',['run','--target',target,'--module','modifier_fixture'],consumer,`release-modifiers-${target}.log`));
    assert.equal(modifiers.length,7);
    const expectedAcceptance={counted:[true,false,false,false,true,false],text:[true,false,false,false],integer:[true,true,false,false,false],number:[true,false,true,false,false],array:[true,true,false,false,false,false,false,false],object:[true,true,false,false,false],asserted:[true,true,false,false,false]};
    for(const group of modifiers){
      assert.deepEqual(group.cases.map(row=>row.validated),expectedAcceptance[group.name]);
      for(const row of group.cases)assert.equal(row.decoded.accepted,row.validated);
    }
    modifierObservations.push(modifiers);
  }
  assert.deepEqual(modifierObservations[0],modifierObservations[1],'Archive modifier schemas/decoded outputs differ across targets');
  const provenance=JSON.parse(readFileSync(join(library,'priv/regex-src/PROVENANCE.json')));
  for(const [name,record] of Object.entries(provenance.files))assert.equal(sha256(readFileSync(join(library,'priv/regex-src',name))),record.vendoredSha256,name);
  assert.equal(existsSync(join(library,'node_modules')),false);
  const modules=readdirSync(join(root,'build/dev/docs/gargamelle')).filter(name=>name.endsWith('.html'));
  assert.ok(modules.includes('gargamelle.html'));assert.ok(!modules.includes('schema_fixtures.html'));
  assert.ok(existsSync(join(root,'build/dev/docs/gargamelle/gargamelle/encoding.html')));
  const config=readFileSync(join(root,'gleam.toml'),'utf8');
  const docs=join(root,'build/dev/docs/gargamelle');
  const pages=[...config.matchAll(/^path = "([^"]+\.html)"$/gm)].map(match=>match[1]);
  for(const page of ['index.html','gargamelle.html','gargamelle/encoding.html','gargamelle/boundary.html','gargamelle/diagnostics.html',...pages]){
    const html=readFileSync(join(docs,page),'utf8');
    if(['index.html','gargamelle.html','gargamelle/encoding.html','gargamelle/boundary.html','gargamelle/diagnostics.html'].includes(page)){
      for(const [,linkedVersion] of html.matchAll(/https:\/\/hexdocs\.pm\/gargamelle\/(\d+\.\d+\.\d+)\//g))
        assert.equal(linkedVersion,version,`Stale versioned documentation link in ${page}`);
    }
    assert.ok(html.includes('https://github.com/vistuleB/gargamelle'),`Missing public repository link in ${page}`);
    assert.match(html,/>Repository<\/a>/,`Missing repository label in ${page}`);
    assert.match(html,/>Source archive<\/a>/,`Missing source archive label in ${page}`);

    for(const [,rawHref] of html.replace(/<pre\b[^>]*>[\s\S]*?<\/pre>/g,'').matchAll(/href="([^"]+)"/g)){
      const prefix=`https://hexdocs.pm/gargamelle/${version}/`;
      const href=rawHref.startsWith(prefix)?rawHref.slice(prefix.length)||'index.html':rawHref;
      if(/^(?:https?:|mailto:|data:)/.test(href))continue;
      const url=new URL(href,'https://docs.invalid/'+page);
      const target=join(docs,decodeURIComponent(url.pathname.slice(1)));
      assert.ok(existsSync(target),`Broken local link in ${page}: ${href}`);
      if(url.hash&&target.endsWith('.html')){
        const anchor=decodeURIComponent(url.hash.slice(1));
        const targetHtml=readFileSync(target,'utf8');
        assert.ok(targetHtml.includes(`id="${anchor}"`),`Broken anchor in ${page}: ${href}`);
      }
    }
  }
  const assets=readFileSync(join(root,'docs/renderer-assets.md'),'utf8');
  for(const [name,language] of [['reference.css','css'],['reference.js','javascript']]){
    assert.ok(assets.includes('```'+language+'\n'+readFileSync(join(root,'documentation',name),'utf8').trimEnd()+'\n```'),`Stale renderer asset: ${name}`);
  }
  assert.equal(fingerprint().digest,before.digest,'Source changed during release preparation');
  const report={status:'prepared',version,generatedAt:new Date().toISOString(),source:before,
    platform:process.platform,architecture:process.arch,commands,logs,
    versions:{node:process.version,unicode:process.versions.unicode,gleam:run('gleam',['--version']).trim(),otp:run('erl',['-noshell','-eval','io:format("~s", [erlang:system_info(otp_release)]), halt().']).trim(),beam:run('erl',['-noshell','-eval','io:format("~s", [erlang:system_info(system_version)]), halt().']).trim()},
    archive:{path:`build/gargamelle-${version}.tar`,sha256:sha256(readFileSync(archive)),contentsSha256:sha256(readFileSync(contents)),members:entries},
    counts:{javascript:js.counts,nativeGroups:17,nativeOperatorMutants:mutations.mutants.length,nativeOfficialCases:official.cases,nativeGeneratedPairs:generated.pairs,nativeDecodedOutputs:generated.coverage.decoded},
    support:{javascript:process.version,nativeEvidence:`${process.platform} ${process.arch} / OTP ${official.otp} / explicit C helper installation`,unqualified:['Platforms and OTP versions outside this recorded run','Other deployment tooling'],unsupported:['Windows native helper'],browserEvidence:'Separate manual browser gate; see docs/browser-support.md',unverifiedJavaScriptHosts:['Bun','Deno','Older and mobile browsers']},
    reviewRequired:['V08 preservation argument','Declared Erlang support scope and remaining platform qualification'],
    scope:'Prepared local candidate; not publication approval or broad Erlang support qualification'};
  writeFileSync(reportPath,JSON.stringify(report,null,2)+'\n');
  console.log(`PREPARED: ${version}; both target gates, docs, archive inspection and fresh consumers passed. Publication and broad Erlang qualification remain separate.`);
} catch(error){
  writeFileSync(reportPath,JSON.stringify({status:'failed',source:before.digest,error:String(error),logs},null,2)+'\n');
  throw error;
} finally {if(directory)rmSync(directory,{recursive:true,force:true});}
