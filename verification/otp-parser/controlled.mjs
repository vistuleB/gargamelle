import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {fingerprint,sha256} from '../evidence.mjs';
const build=process.argv[2]??'build/dev/erlang';
const source=fingerprint();
const seed=0x080c011;let state=seed;
const next=()=>state=(Math.imul(state,1664525)+1013904223)>>>0;
const shuffle=xs=>{const out=[...xs];for(let i=out.length-1;i>0;i--){const j=(next()>>>8)%(i+1);[out[i],out[j]]=[out[j],out[i]];}return out;};
const provider=JSON.stringify({type:'cloze',version:1,data:{entries:Array.from({length:100},(_,i)=>({blankId:`blank_${i}`,response:'Brainy',accepted:['Brainy','Jokey'],correct:true})),correct:100,total:100}});
const payloads=[
 ['small provider result',JSON.stringify({type:'cloze',version:1,data:{correct:2,total:2,entries:[]}}),3000],
 ['provider entries eligible',provider,150],
 ['provider entries fallback IDs',provider.replaceAll('blank_','blank-'),150],
 ['long scalar text',JSON.stringify({text:'A scalar sentence with é and 💜. '.repeat(1000)}),100],
 ['numeric array',JSON.stringify(Array.from({length:1000},(_,i)=>i/7+1)),100],
 ['ordinary guarded text',JSON.stringify({text:'Ordinary text includes -0; the guard falls back.'}),3000],
 ['small configuration',JSON.stringify({theme:'dark',language:'en',limit:25,enabled:true}),3000],
 ['nested mixed JSON',JSON.stringify({groups:Array.from({length:20},(_,i)=>({id:i+1,label:'A label é',items:[null,true,i+1,{nested:['Brainy','Jokey']}]}))}),200],
 ['overwritten surrogate','{"x":"\\ud800","x":1}',1500],
 ['rejected surrogate','"\\ud800"',1500],
];
const variants=['reference','copying_hybrid'];
const rounds=5;
function run(variant,payload){return new Promise((resolve,reject)=>{
 const p=spawn('escript',['verification/otp-parser/isolated.escript',build,variant],{env:{...process.env,ERL_FLAGS:' +S 1:1'}});
 let out='',err='';const timeout=setTimeout(()=>{p.kill();reject(new Error('Probe timed out'));},30000);
 p.stdout.on('data',x=>out+=x);p.stderr.on('data',x=>err+=x);p.on('error',reject);
 p.on('close',code=>{clearTimeout(timeout);try{assert.equal(code,0,err+out);resolve(JSON.parse(out));}catch(e){reject(e);}});
 p.stdin.end(JSON.stringify({source:payload[1],iterations:payload[2]})+'\n');
});}
const runs=[];
for(let round=0;round<rounds;round++){
 for(const index of shuffle(payloads.map((_,i)=>i))){
  for(const variant of shuffle(variants)){
   const result=await run(variant,payloads[index]);
   assert.equal(result.retained_bytes,128);assert.equal(result.schedulers,1);
   runs.push({round,index,variant,result});
  }
 }
 console.log(`Completed isolated round ${round+1}/${rounds}`);
}
const median=xs=>[...xs].sort((a,b)=>a-b)[Math.floor(xs.length/2)];
const summaries=payloads.map(([name,text,iterations],index)=>{
 const group=runs.filter(x=>x.index===index);
 assert.equal(new Set(group.map(x=>x.result.result_sha256)).size,1,`Public results differ: ${name}`);
 assert.equal(new Set(group.map(x=>x.result.route)).size,1,`Routes differ: ${name}`);
 const timings=Object.fromEntries(variants.map(variant=>{const values=group.filter(x=>x.variant===variant).map(x=>median(x.result.samples.map(s=>s.microseconds)));return [variant,{median:median(values),min:Math.min(...values),max:Math.max(...values),vmMedians:values}];}));
 return {name,bytes:Buffer.byteLength(text),iterations,route:group[0].result.route,timings,speedup:timings.reference.median/timings.copying_hybrid.median};
});
assert.equal(fingerprint().digest,source.digest);
const report={source,compiledPublicModuleSha256:sha256(readFileSync(`${build}/gargamelle/_gleam_artefacts/gargamelle.erl`)),seed,rounds,platform:process.platform,architecture:process.arch,node:process.version,workloadSha256:sha256(JSON.stringify(payloads)),runs,summaries,exactPublicResultsMatch:true,retentionChecksPassed:true,method:['One variant and workload per fresh VM; compilation and startup excluded','One BEAM scheduler; 200 warmups; three samples per VM; five independent VMs per variant/workload','Seeded randomized workload and variant order; variants never run concurrently','Full public parse with existing typed constructor callbacks; hybrid copies strings','Synthetic representative payloads, not measured production traffic; no aggregate traffic weighting','Runtime/dependency versions recorded; within-machine comparisons only','Validation/decoding/handlers not included in timing; retention smoke check runs afterwards']};
mkdirSync('reports',{recursive:true});writeFileSync('reports/otp-parser-controlled.json',JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(summaries.map(x=>({name:x.name,route:x.route,reference:x.timings.reference.median,hybrid:x.timings.copying_hybrid.median,speedup:x.speedup}))));
