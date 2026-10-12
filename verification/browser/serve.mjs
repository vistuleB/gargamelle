import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {cpSync,existsSync,mkdirSync,mkdtempSync,readFileSync,readdirSync,writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {join,resolve,basename} from 'node:path';
import {root,fingerprint,sha256} from '../evidence.mjs';
import {corpus} from '../generated-corpus.mjs';
import {reference} from '../reference.mjs';
import {compileOracle} from '../oracle.mjs';
import {compileSupplementary} from '../supplementary-oracle.mjs';
import {classifySplit} from '../oracle-classification.mjs';
import {knownUnicodeDifference} from './regex-boundary.mjs';

assert.equal(process.version,'v24.10.0','Use the Unicode 16 Node reference');
const directory=join(root,'reports/browser-verification');mkdirSync(directory,{recursive:true});
const workspace=mkdtempSync(join(directory,'workspace-'));
const before=fingerprint();
const baseline=spawnSync('gleam',['test','--target','javascript'],{cwd:root,encoding:'utf8',timeout:60000,maxBuffer:5*1024*1024});
writeFileSync(join(directory,'node-typed.log'),baseline.stdout+baseline.stderr);
assert.ifError(baseline.error);assert.equal(baseline.status,0,baseline.stdout+baseline.stderr);
cpSync(join(root,'build/dev/javascript'),join(workspace,'build/dev/javascript'),{recursive:true,dereference:true,filter:path=>basename(path)!=='priv'});
for(const path of ['verification/generated-api.mjs','verification/recipe-model.mjs','verification/browser/client.mjs','verification/browser/evaluate.mjs','verification/browser/index.html']){
 mkdirSync(join(workspace,path,'..'),{recursive:true});cpSync(join(root,path),join(workspace,path));
}
mkdirSync(join(workspace,'assets'));for(const name of ['reference.css','reference.js'])cpSync(join(root,'documentation',name),join(workspace,'assets',name));
// Frozen local HexDocs preview for the release editorial review.
const renderedDocs=join(root,'build/dev/docs/gargamelle');
if(existsSync(renderedDocs))cpSync(renderedDocs,join(workspace,'docs'),{recursive:true});
const runner=join(workspace,'build/dev/javascript/gargamelle/gargamelle_test.mjs');
let runnerSource=readFileSync(runner,'utf8');
assert.equal(runnerSource.split('import * as $gleeunit from "../gleeunit/gleeunit.mjs";').length,2);
runnerSource=runnerSource.replace('import * as $gleeunit from "../gleeunit/gleeunit.mjs";','').replace(/export function main\(\) \{\s*return \$gleeunit\.main\(\);\s*\}/,'');
assert.ok(!runnerSource.includes('$gleeunit'));writeFileSync(runner,runnerSource);
const typed=readdirSync(join(root,'test')).filter(n=>n.endsWith('_test.gleam')).sort().map(name=>{
 const path='/build/dev/javascript/gargamelle/'+name.replace('.gleam','.mjs');
 const source=readFileSync(join(workspace,path),'utf8');
 const tests=[...source.matchAll(/export function (\w+_test)\(/g)].map(m=>m[1]);
 return {path,tests};
});
assert.equal(typed.reduce((n,m)=>n+m.tests.length,0),120);
const {build,s}=await import('../generated-api.mjs');
const {evaluate,regexCases,nativeJSRegex}=await import('./evaluate.mjs');
let splits=0,accepted=0,pairs=0;
console.log('Checking generated Node baseline against independent validators and outputs…');
const rows=[];
for(const [index,row] of corpus().entries()){
 const definition=build(row.recipe),schema=s.schema_string(definition, s.JsonFormat$Compact$const),ajv=compileOracle(JSON.parse(schema)),hyperjump=await compileSupplementary(JSON.parse(schema));
 const expected=[];
 for(const input of row.inputs){
  const value=JSON.parse(input),result=evaluate(definition,input),a=ajv(value),h=hyperjump(value),ref=reference(row.recipe,value);
  if(classifySplit(JSON.parse(schema),value,a,h))splits++;
  assert.equal(h.accepted,ref.accepted);assert.equal(result.accepted,ref.accepted);
  if(result.accepted){assert.deepEqual(result.decoded,JSON.parse(JSON.stringify(ref.value)));accepted++;}
  expected.push(result);pairs++;
 }
 rows.push({...row,schema,expected});
}
assert.equal(rows.length,886);assert.equal(pairs,17788);assert.equal(accepted,6459);
assert.equal(fingerprint().digest,before.digest,'Source changed during fixture preparation');
const fixture={source:before.digest,typed,rows},fixtureText=JSON.stringify(fixture);
writeFileSync(join(workspace,'fixture.json'),fixtureText);
const modules={};
function hashes(dir){for(const item of readdirSync(dir,{withFileTypes:true})){const path=join(dir,item.name);if(item.isDirectory())hashes(path);else modules[path.slice(workspace.length+1)]=sha256(readFileSync(path));}}
hashes(workspace);
const expectedRegex=regexCases.map(nativeJSRegex);
const baselineReport={source:before,versions:{node:process.version,unicode:process.versions.unicode},typedTests:120,definitions:rows.length,pairs,decoded:accepted,classifiedAjvSplits:splits,fixtureSha256:sha256(fixtureText),artifactHashes:modules,
 adaptation:'Only gleeunit Node runner import and unused main removed from copied gargamelle_test.mjs; library and assertion bodies unchanged'};
writeFileSync(join(directory,'baseline.json'),JSON.stringify(baselineReport,null,2)+'\n');
const allowed=new Set(Object.keys(modules));
let results=0;
const server=createServer(async(req,res)=>{
 try{
  const path=new URL(req.url,'http://128.0.0.1').pathname;
  if(req.method==='POST'&&path==='/result'){
   // Decode UTF-8 across chunk boundaries, including supplementary characters.
   req.setEncoding('utf8');
   let body='';for await(const chunk of req){body+=chunk;if(body.length>20*1024*1024)throw new Error('Result too large');}
   const report=JSON.parse(body),differences=[];
   let failure;
   try{
    assert.equal(report.source,before.digest);assert.equal(report.status,'passed');
    assert.deepEqual(report.typed,typed.flatMap(m=>m.tests.map(t=>m.path+':'+t)));
    assert.deepEqual(report.generated,rows.map((r,index)=>({index,schema:r.schema,cases:r.expected})));
    assert.equal(report.regex.length,expectedRegex.length);assert.equal(report.renderer.length,19);
    for(const [index,entry] of report.regex.entries())if(JSON.stringify(entry)!==JSON.stringify(expectedRegex[index]))differences.push({index,...regexCases[index],node:expectedRegex[index],browser:entry});
    assert.ok(differences.every(knownUnicodeDifference),'Unclassified browser/Node regex difference');
   }catch(error){failure=String(error);}
   const label=new URL(req.url,'http://128.0.0.1').searchParams.get('browser')??'run-'+(++results);
   assert.ok(/^[a-zA-Z0-9_-]+$/.test(label));
   const record={...report,serverStatus:failure?'failed':'passed',serverFailure:failure,nodeRegexDifferences:differences,baselineSha256:sha256(readFileSync(join(directory,'baseline.json')))};
   writeFileSync(join(directory,label+'.json'),JSON.stringify(record)+'\n');
   console.log(JSON.stringify({file:label+'.json',userAgent:report.userAgent,status:record.serverStatus,regexDifferences:differences.length,failure}));
   res.writeHead(200,{'content-type':'application/json'});res.end(JSON.stringify({accepted:!failure,report:label+'.json',regexDifferences:differences.length,failure}));return;
  }
  if(req.method!=='GET')throw new Error('Unsupported method');
  const name=path==='/'?'verification/browser/index.html':decodeURIComponent(path.slice(1));
  if(!allowed.has(name)||!existsSync(resolve(workspace,name))){res.writeHead(404);res.end('Not found');return;}
  const file=readFileSync(join(workspace,name));
  const type=name.endsWith('.mjs')||name.endsWith('.js')?'text/javascript':name.endsWith('.json')?'application/json':name.endsWith('.css')?'text/css':name.endsWith('.woff2')?'font/woff2':name.endsWith('.woff')?'font/woff':name.endsWith('.svg')?'image/svg+xml':name.endsWith('.png')?'image/png':'text/html';
  res.writeHead(200,{'content-type':type,'cache-control':'no-store'});res.end(file);
 }catch(error){res.writeHead(400,{'content-type':'application/json'});res.end(JSON.stringify({error:String(error)}));}
});
server.listen(0,'128.0.0.1',()=>{
 const url='http://128.0.0.1:'+server.address().port+'/';
 writeFileSync(join(directory,'server.json'),JSON.stringify({url,source:before.digest})+'\n');
 console.log('BROWSER VERIFICATION READY '+url);
});
for(const signal of ['SIGTERM','SIGINT'])process.on(signal,()=>server.close(()=>process.exit(0)));
