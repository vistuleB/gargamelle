import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {fingerprint,sha256} from '../evidence.mjs';
const build=process.argv[2];
assert.ok(build,'Pass the build/dev/erlang directory from a freshly compiled matching checkout.');
const source=fingerprint();
const entries=JSON.stringify({entries:Array.from({length:100},(_,i)=>({id:`blank_${i}`,response:'Brainy',accepted:['Brainy','Jokey'],correct:true}))});
const requests=[
 {name:'small provider result',source:'{"type":"cloze","version":1,"data":{"correct":2,"total":2,"entries":[]}}',iterations:4000},
 {name:'provider entries OTP route',source:entries,iterations:150},
 {name:'provider entries zero fallback',source:entries.replaceAll('blank_','blank-'),iterations:150},
 {name:'long scalar text',source:JSON.stringify({text:'A scalar sentence with é and 💜. '.repeat(1000)}),iterations:100},
 {name:'numeric array',source:JSON.stringify(Array.from({length:1000},(_,i)=>i/7+1)),iterations:100},
 {name:'overwritten surrogate',source:'{"x":"\\ud800","x":1}',iterations:1000},
 ...['-0','-0e0','{"x":1e400,"x":1}','"\\ud800"','[1e400,]'].map(text=>({name:text,source:text,iterations:1000})),
];
const run=spawnSync('escript',['verification/otp-parser/full-path.escript',build],{input:requests.map(r=>JSON.stringify(r)).join('\n')+'\n',encoding:'utf8',timeout:90000});
assert.ok(!run.error,`${run.error ?? ''} ${run.stderr} ${run.stdout}`); assert.equal(run.status,0,run.stderr+run.stdout);
const result=JSON.parse(run.stdout);
assert.equal(result.reference.decoded_retained_string.bytes,128);
assert.equal(result.reference.decoded_retained_string.referenced_bytes,128);
assert.equal(result.copying_hybrid.decoded_retained_string.referenced_bytes,128);
assert.equal(result.hybrid.decoded_retained_string.referenced_bytes,result.source_bytes);
const median=xs=>[...xs].sort((a,b)=>a-b)[Math.floor(xs.length/2)];
const costs=requests.map((r,i)=>({name:r.name,bytes:Buffer.byteLength(r.source),reference:median(result.reference.costs[i].samples),hybrid:median(result.hybrid.costs[i].samples),copyingHybrid:median(result.copying_hybrid.costs[i].samples)}));
assert.equal(fingerprint().digest,source.digest);
mkdirSync('reports',{recursive:true});
writeFileSync('reports/otp-parser-full-path.json',JSON.stringify({source,compiledPublicModuleSha256:sha256(readFileSync(`${build}/gargamelle/_gleam_artefacts/gargamelle.erl`)),platform:process.platform,architecture:process.arch,result,costs,limitations:['Local machine only; warmed medians, not release qualification','Variants run sequentially in one VM; phase/heap effects are uncontrolled and fallback timings vary','Public parsing included; timings do not include definition validation or handler execution','Retained backing sizes measure string sharing, not total allocation or process memory','Runtime variant loaded only inside disposable escript VM; production files unchanged']},null,2)+'\n');
console.log(JSON.stringify({costs,retention:{sourceBytes:result.source_bytes,reference:result.reference.decoded_retained_string,hybrid:result.hybrid.decoded_retained_string,copyingHybrid:result.copying_hybrid.decoded_retained_string,default:result.default_otp_retained_string,copying:result.copying_otp_retained_string}}));
