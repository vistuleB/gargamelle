import * as b from '../build/dev/javascript/gargamelle/gargamelle/boundary.mjs';
// Bounded measurements, no performance threshold or allocation claim.
import {performance} from 'node:perf_hooks';
import {writeFileSync,mkdirSync} from 'node:fs';
import assert from 'node:assert/strict';
import * as e from '../build/dev/javascript/gargamelle/gargamelle/encoding.mjs';
import * as s from '../build/dev/javascript/gargamelle/gargamelle.mjs';
import {Ok,Error as Rejected,toList} from '../build/dev/javascript/gargamelle/gleam.mjs';
import {fingerprint} from './evidence.mjs';
const unwrap=result=>{assert.ok(result.isOk());return result[0];};
const median=values=>[...values].sort((a,b)=>a-b)[Math.floor(values.length/2)];
const measure=run=>{
  for(let i=0;i<20;i++)unwrap(run());
  const timings=[];
  for(let n=0;n<5;n++){
    const start=performance.now();for(let i=0;i<100;i++)unwrap(run());
    timings.push((performance.now()-start)*1000/100);
  }
  return {medianMicroseconds:median(timings),samples:timings};
};
const rows=[];
for(const length of [10,1000]){
  const raw=Array.from({length},(_,i)=>'Brainy '+i+' 😀');
  const value=toList(raw),encoder=e.array(e.string()),definition=s.array(s.string());
  const structural=s.contract(definition);
  const semantic=s.require(structural,'Names nonempty',names=>[...names].every(name=>name.length>0)?new Ok(undefined):new Rejected(toList([new s.Violation('','Empty name')])));
  const encoded=unwrap(e.encode_json(encoder,value));
  assert.deepEqual(JSON.parse(s.to_string(encoded,s.JsonFormat$Compact$const)),raw);
  const plain=e.codec(encoder,structural),checked=e.codec(encoder,semantic);
  const receiver=b.output(encoder,b.json(semantic,s.verified_json));
  rows.push({kind:'array-of-text',items:length,bytes:Buffer.byteLength(JSON.stringify(raw)),costs:{
    hostStringifyThenAdmission:measure(()=>s.parse(JSON.stringify(raw))),
    encodeJson:measure(()=>e.encode_json(encoder,value)),
    structuralEncode:measure(()=>e.encode(plain,value)),
    semanticEncode:measure(()=>e.encode(checked,value)),
    semanticSend:measure(()=>b.send(receiver,value)),
  }});
}
const report={status:'measured',source:fingerprint().digest,node:process.version,warmup:20,samples:5,iterationsPerSample:100,rows,
  scope:'Bounded JavaScript measurements, not thresholds, a cross-target comparison or an allocation profile. Host stringify is a reference for the JSON admission cost, not a typed encoder replacement.'};
mkdirSync('reports',{recursive:true});writeFileSync('reports/encoding-costs.json',JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
