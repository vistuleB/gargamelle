import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdirSync,appendFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {performance} from 'node:perf_hooks';
const mode=process.argv[2];assert.ok(['prepare','dependencies'].includes(mode));
mkdirSync('reports',{recursive:true});
const file=resolve('reports/release-timings.jsonl');
const env={...process.env,GARGAMELLE_TRACE_FILE:file,NODE_OPTIONS:[process.env.NODE_OPTIONS??'',`--import=${resolve('verification/release-timing-preload.mjs')}`].filter(Boolean).join(' ')};
const commands=mode==='prepare'?[['npm',['run','prepare:release']]]:[['npm',['ci']],['gleam',['deps','download']]];
for(const [command,args] of commands){
 const id=`root-${mode}-${Date.now()}`;const started=performance.now();env.GARGAMELLE_TRACE_PARENT=id;
 appendFileSync(file,JSON.stringify({event:'start',id,parent:null,pid:process.pid,kind:'stage',command,args,at:Date.now()})+'\n');
 const result=spawnSync(command,args,{env,stdio:'inherit'});
 const durationMs=performance.now()-started;
 appendFileSync(file,JSON.stringify({event:'end',id,pid:process.pid,at:Date.now(),durationMs,status:result.status,error:result.error?.message})+'\n');
 console.log(`TIMED ${command} ${args.join(' ')}: ${(durationMs/1000).toFixed(3)} seconds`);
 assert.ifError(result.error);assert.equal(result.status,0);
}
