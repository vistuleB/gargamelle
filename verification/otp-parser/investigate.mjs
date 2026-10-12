import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {fingerprint,sha256} from '../evidence.mjs';
const copying=process.argv.includes('--copy-strings');
const source=fingerprint();mkdirSync('reports',{recursive:true});
const run=requests=>{
  const result=spawnSync('escript',['verification/otp-parser/probe.escript',...(copying?['copy']:[])],{input:requests.map(x=>JSON.stringify(x)).join('\n')+'\n',encoding:'utf8',timeout:90000,maxBuffer:256*1024*1024});
  assert.ifError(result.error);assert.equal(result.status,0,result.stderr);
  const rows=result.stdout.trim().split('\n').map(line=>JSON.parse(line));assert.equal(rows.length,requests.length);return rows;
};
const bits=n=>{const b=Buffer.alloc(8);b.writeDoubleBE(n);return b.readBigUInt64BE().toString();};
function snapshot(v){
  if(v===null)return {type:'null'};
  if(typeof v==='boolean')return {type:'boolean',value:v};
  if(typeof v==='number')return {type:'number',bits:bits(v)};
  if(typeof v==='string')return {type:'string',value:v};
  if(Array.isArray(v))return {type:'array',values:v.map(snapshot)};
  return {type:'object',entries:Object.keys(v).map(k=>[k,snapshot(v[k])])};
}
function domain(v){
  if(typeof v==='number'&&!Number.isFinite(v))return 'nonfinite_number';
  if(typeof v==='string'&&!v.isWellFormed())return 'non_scalar_string';
  if(v&&typeof v==='object'){
    if(!Array.isArray(v)&&Object.keys(v).some(k=>!k.isWellFormed()))return 'non_scalar_string';
    for(const child of Object.values(v)){const e=domain(child);if(e)return e;}
  }
}
function expected(text){let value;try{value=JSON.parse(text);}catch{return {error:'syntax'};}
 const e=domain(value);return e?{error:e}:{value:snapshot(value)};}
function enumerate(value){
 if(value.type==='array')return {...value,values:value.values.map(enumerate)};
 if(value.type==='object'){
  const entries=Object.fromEntries(value.entries);return {...value,entries:Object.keys(entries).map(k=>[k,enumerate(entries[k])])};
 }return value;
}
const fixed=['null','true','false','{}','[]','-0','-0e0','-0.0','-0E+10','-0e-400',
 '1e400','[1e400,]','{"x":1e400,"x":1}','{"x":1,"x":1e400}',
 '{"x":"\\ud800","x":1}','{"x":1,"x":"\\ud800"}',
 '{"z":1,"a":2,"z":3}','{"10":1,"2":2,"x":3,"10":4}',
 '{"__proto__":1,"constructor":2}','"\\ud83d\\udc9c"','"\\ud800"',
 '"\\udc00"','"\\ud800x"','{"\\ud800":1}','["\\ud800",]',
 '1 2','01','-01','1.','1e','1e+','--1','+1','truex','{"x":1,}',
 '1e-400','5e-324','1.7976931348623157e308','9007199254740993',
 '1234567890123456789012345678901234567890','"text -0 inside a string"'];
for(let n=0xd800;n<=0xdfff;n++)fixed.push(`"\\u${n.toString(16)}"`,`{"x":"\\u${n.toString(16)}","x":1}`);
const seed=0x080c0de;let state=seed;const next=()=>state=(Math.imul(state,1664525)+1013904223)>>>0;
const pick=n=>(next()>>>8)%n;
const atoms=['null','true','false','0','-0','-0e0','-0.25','1','1.25','1e400','5e-324','9007199254740993','"Brainy"','"💜"','"\\ud800"','"\\ud83d\\udc9c"'];
const keys=['a','z','2','10','__proto__','constructor','', 'a/~','💜'];
function generate(depth){
 const choice=pick(4);if(!depth||choice<2)return atoms[pick(atoms.length)];
 const length=1+pick(3);
 if(choice===2)return '['+Array.from({length},()=>generate(depth-1)).join(',')+']';
 return '{'+Array.from({length},()=>JSON.stringify(keys[pick(keys.length)])+':'+generate(depth-1)).join(',')+'}';
}
const generated=Array.from({length:5000},()=>generate(3));
const malformed=generated.slice(0,500).map(text=>text.slice(0,-1));
const texts=[...fixed,...generated,...malformed];
const distinctGenerated=new Set(generated).size;assert.ok(distinctGenerated>1000,`Insufficient generated diversity: ${distinctGenerated}`);
const [metadata]=run([{metadata:true}]);
const replies=run(texts.map(source=>({source})));
const mismatches=[],routes={};
for(const [i,r] of replies.entries()){
 assert.deepEqual(r.hybrid,r.reference,texts[i]);
 const js=expected(texts[i]);
 // Native admission prioritizes nonfinite numbers when both domains fail;
 // the existing contract does not promise cross-target domain-error precedence.
 if(js.error){assert.ok(r.reference.error,texts[i]);if(js.error==='syntax')assert.equal(r.reference.error,'syntax',texts[i]);else assert.ok(['nonfinite_number','non_scalar_string'].includes(r.reference.error));}
 else assert.deepEqual(enumerate(r.reference.value),js.value,texts[i]);
 if(JSON.stringify(r.adapted)!==JSON.stringify(r.reference))mismatches.push({source:texts[i],reference:r.reference,adapted:r.adapted});
 routes[r.route]=(routes[r.route]??0)+1;
}
const blockers={
 negativeZero:mismatches.some(r=>r.source==='-0'),
 overwrittenSurrogate:mismatches.some(r=>r.source==='{"x":"\\ud800","x":1}'),
};
const providerLike=JSON.stringify({type:'cloze',version:1,data:{entries:Array.from({length:100},(_,i)=>({blankId:`blank-${i}`,response:'Brainy',accepted:['Brainy','Jokey'],correct:true})),correct:100,total:100}});
const inputs=[
 ['small provider result',JSON.stringify({type:'cloze',version:1,data:{correct:2,total:2,entries:[]}}),4000],
 ['provider-like entries (zero text fallback)',providerLike,150],
 ['provider-like entries (OTP route)',providerLike.replaceAll('blank-', 'blank_'),150],
 ['long scalar text',JSON.stringify({text:'A scalar sentence with é and 💜. '.repeat(1000)}),100],
 ['numeric array',JSON.stringify(Array.from({length:1000},(_,i)=>i/7+1)),100],
 ['false-positive zero in text',JSON.stringify({text:'Ordinary text includes -0, so the conservative guard falls back.'}),4000],
 ['overwritten surrogate','{"x":"\\ud800","x":1}',4000],
];
const measurements=run(inputs.map(([,benchmark,iterations])=>({benchmark,iterations})));
const median=xs=>[...xs].sort((a,b)=>a-b)[Math.floor(xs.length/2)];
const costs=inputs.map(([name,text,iterations],i)=>({name,bytes:Buffer.byteLength(text),iterations,samples:measurements[i],medianMicroseconds:Object.fromEntries(Object.entries(measurements[i]).map(([key,rows])=>[key,median(rows.map(r=>r.microseconds_per_parse))]))}));
assert.equal(fingerprint().digest,source.digest);
const report={status:'investigation-complete',copying,platform:process.platform,architecture:process.arch,node:process.version,seed,distinctGenerated,source,metadata,cases:texts.length,fixed:fixed.length,generated:generated.length,truncated:malformed.length,callbackOnlyDivergences:mismatches.length,blockers,examples:mismatches.slice(0,12),routes,hybridMatchesReference:true,independentNodeAdmissionAndNumericChecks:true,corpusSha256:sha256(JSON.stringify(texts)),costs,limitations:['One recorded machine/runtime per report; investigation only, not release qualification','Reference copy exposes ordered parser mode only; production source unchanged','Hybrid retains the complete custom parser and scans conservatively for -0','Callback-only adapted benchmark results on incompatible inputs are diagnostic, not comparable performance','Parse-stage snapshots; public opaque construction/conversion is not included','Reductions are recorded; retained-memory/allocation claims are not made','Domain-error precedence is not compared when both numeric and scalar domains fail'],recommendation:mismatches.length?'Do not replace the parser with callback-only OTP; consider hybrid only as a separately justified optimization.':'Callback adapter passed this corpus; full public-parser integration and operational-failure qualification are still required.'};
writeFileSync(copying?'reports/otp-parser-copying-investigation.json':'reports/otp-parser-investigation.json',JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({cases:report.cases,divergences:report.callbackOnlyDivergences,distinctGenerated,routes,costs:costs.map(r=>({name:r.name,...r.medianMicroseconds}))}));
