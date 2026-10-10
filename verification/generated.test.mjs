import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, writeFileSync } from 'node:fs';
import {reference} from './reference.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';
import {classifySplit} from './oracle-classification.mjs';
import { compileOracle } from './oracle.mjs';
import { minimize,minimizeAsync } from './generated-shrink.mjs';
import { retainOperationalFailure, checkpointCase, clearCheckpoint } from './generated-retention.mjs';
import { build,evaluate,evaluateText,emitted,s,allKinds,childNodes,proposal,specimen } from './generated-api.mjs';

const seeds=[0x10203040,0x91abcdef,0x12345678,0xdeadbeef,0x71423,0x55555555,0xabcdef01,0x37891,0x76543210,0xfedcba98];
const common=[null,true,false,0,1,-1,1.5,'','x','a','ab','😀','e\u0301','\0','\ud800',[],{},[null],{value:null},Number.MAX_SAFE_INTEGER+1];
function random(seed){let x=seed>>>0;return n=>{x^=x<<13;x^=x>>>17;x^=x<<5;return (x>>>0)%n;};}
function generated(r,depth){
 if(depth===0){const a=specimen(allKinds[r(8)]);if(a.kind==='constant')a.value=[null,true,false,'c',-1,0,1][r(7)];if(a.kind==='string'&&r(2)){a.min=r(2);a.max=3;if(r(2))a.patterns=['a','b','a'];}if(a.kind==='integer'&&r(2)){a.min=-3;a.max=3;}if(a.kind==='number'&&r(2)){a.min=-1.5;a.max=2.5;a.exclusiveMin=!!r(2);a.exclusiveMax=!!r(2);}return a;}
 const kind=allKinds[8+r(allKinds.length-8)];
 const a=specimen(kind,generated(r,depth-1));
 const names=['__proto__','constructor','toString','','a/b','~1','10','2','01','😀'];
 if(kind==='conditional'&&r(2))a.alternative={kind:'boolean'};
 if(kind==='record'){a.open=!!r(2);const offset=r(names.length);a.fields.forEach((f,i)=>f.name=names[(offset+i)%names.length]);}
 if(kind==='tagged'){a.tag=names[r(names.length)];a.branches.forEach((b,i)=>b.tag=names[(i+r(3)*2)%names.length]);if(a.branches[0].tag===a.branches[1].tag)a.branches[1].tag+='-other';}

 if(kind==='any'||kind==='one'){if(r(2))a.children.push(specimen('boolean'));if(r(4)===0)a.children.push(a.children[0]);}
 return a;
}
function mutations(v){
 if(Array.isArray(v))return [[],[...v,...v,...v,...v],v.map((x,i)=>i===0?false:x)];
 if(v&&typeof v==='object'){const entries=Object.entries(v);return [{},{...v,unexpected:true},Object.fromEntries(entries.slice(1)),Object.fromEntries(entries.map(([k,x],i)=>[k,i===0?false:x]))];}
 if(typeof v==='string')return ['',v+'!',v+v+v+v,v.length? v.slice(1):'x'];
 if(typeof v==='number')return [v-1,v+1,v+0.5];
 return [null,false,'x'];
}
// Greedy structural shrinking retains a discrepancy, not an assumed validity class.
async function discrepancy(recipe,value){value=JSON.parse(JSON.stringify(value));const d=build(recipe),schema=emitted(d),oracle=(await compileSupplementary(schema))(value),actual=evaluate(d,value);return oracle.accepted!==actual.accepted?{schema,oracle,actual}:null;}
async function retainFailure(recipe,value,context,details){
 mkdirSync(new URL('./generated-failures/',import.meta.url),{recursive:true});
 const file=new URL(`./generated-failures/${context.seed}-${context.index}.json`,import.meta.url);
 const report={contractRevision:3,context,original:{recipe,value,details}};
 writeFileSync(file,JSON.stringify(report,null,2)+'\n');
 const reduced=await minimizeAsync(recipe,value,async(a,v)=>!!await discrepancy(a,v));
 report.minimized={...reduced,details:await discrepancy(reduced.recipe,reduced.value)};
 writeFileSync(file,JSON.stringify(report,null,2)+'\n');
 throw new Error(`Differential mismatch retained at ${file.pathname}`);
}
const coverage={constructors:{},edges:{},outcomes:{},depths:{},pairs:0,definitions:0,seeds,depth50:0,nestedOutcomes:{},nodePaths:{},oracleSplits:{},decodedValues:0};
function observe(a){coverage.constructors[a.kind]=(coverage.constructors[a.kind]??0)+1;for(const c of childNodes(a)){const key=a.kind+'>'+c.kind;coverage.edges[key]=(coverage.edges[key]??0)+1;observe(c);}}
async function run(recipe,values,context){
 const checkpoint=checkpointCase(recipe,values,context);
 let d,check,second,text;
 try {
  d=build(recipe);text=s.emit_text(d);assert.equal(s.emit_text(d),text);assert.deepEqual(JSON.parse(s.value_text(s.emit_json(d))),JSON.parse(text));
  check=compileOracle(JSON.parse(text));second=await compileSupplementary(JSON.parse(text)); // includes selected meta-schema validation
 } catch(error) {
  const file=retainOperationalFailure({recipe,context:{...context,stage:'construction-emission-oracle'},error});
  throw new Error(`Definition/harness failure retained at ${file}`,{cause:error});
 }
 observe(recipe);coverage.definitions++;
 for(let inputIndex=0;inputIndex<values.length;inputIndex++){
  const inputText=JSON.stringify(values[inputIndex]),value=JSON.parse(inputText);let expected,actual;
  try{
   const ajv=check(value);expected=second(value);actual=evaluateText(d,inputText);
   const classification=classifySplit(JSON.parse(text),value,ajv,expected);
   if(classification)coverage.oracleSplits[classification]=(coverage.oracleSplits[classification]??0)+1;
   const ref=reference(recipe,value,(path,kind,accepted)=>{
    const key=kind+':'+accepted;
    if(path!=='$')coverage.nestedOutcomes[key]=(coverage.nestedOutcomes[key]??0)+1;
    const location=context.seed+'/'+context.index+path;
    const visits=coverage.nodePaths[location]??={kind,accepted:0,rejected:0};visits[accepted?'accepted':'rejected']++;
   });
   assert.equal(ref.accepted,expected.accepted,'Reference acceptance differs from Hyperjump');
   if(actual.accepted&&ref.accepted){assert.deepEqual(actual.value,ref.value,'Decoded output differs from independent reference');coverage.decodedValues++;}
  }
  catch(error){const file=retainOperationalFailure({recipe,value,context:{...context,inputIndex,stage:'oracle-decode'},error});throw new Error(`Operational failure retained at ${file}`,{cause:error});}
  coverage.pairs++;const key=recipe.kind+':'+expected.accepted;coverage.outcomes[key]=(coverage.outcomes[key]??0)+1;
  if(actual.accepted!==expected.accepted)await retainFailure(recipe,value,{...context,inputIndex},{expected,actual,schema:JSON.parse(text)});
 }
 clearCheckpoint(checkpoint);
}

test('generated definitions: ten fixed seeds, 10000 pairs, depths 0–6',async()=>{
 for(const seed of seeds){const r=random(seed);for(let i=0;i<50;i++){const depth=i%7;coverage.depths[depth]=(coverage.depths[depth]??0)+1;const a=generated(r,depth),valid=proposal(a,r);const inputs=[valid,...mutations(valid),...Array.from({length:8},()=>proposal(a,r))];while(inputs.length<20)inputs.push(common[r(common.length)]);await run(a,inputs.slice(0,20),{seed,index:i,depth});}}
 assert.equal(coverage.pairs,10000);
});

test('every supported generic parent/child combination has differential evidence',async()=>{
 const wrappers=['array','dictionary','record','nullable','any','one','tagged','description','title','map','tuple','property_names','contains','conditional','exclude'];
 for(const parent of wrappers)for(const child of allKinds){const a=specimen(parent,specimen(child));await run(a,[proposal(a),...common],{seed:'edges',index:parent+'-'+child});assert.ok(coverage.edges[parent+'>'+child]);}
 for(const k of allKinds){const a=specimen(k);await run({kind:'array',child:a},[proposal(a),...common].map(v=>[v]),{seed:'nested',index:k});}
 for(const k of allKinds){assert.ok(coverage.nestedOutcomes[k+':true'],k+' nested accepts');assert.ok(coverage.nestedOutcomes[k+':false'],k+' nested rejects');}
 for(const k of allKinds)assert.ok(coverage.constructors[k],k);
 // null and constant/empty types have structural invalid cases, all constructors have both outcomes.
 for(const k of allKinds){assert.ok(coverage.outcomes[k+':true'],k+' accepts');assert.ok(coverage.outcomes[k+':false'],k+' rejects');}
});

test('separate depth-50 nesting corpus',async()=>{
 const corruptLeaf=v=>Array.isArray(v)?v.map(corruptLeaf):v&&typeof v==='object'?Object.fromEntries(Object.entries(v).map(([k,x])=>[k,corruptLeaf(x)])):false;
 for(const kind of ['array','dictionary','record','nullable','any','one','description','title','map','tuple','property_names','contains','conditional','exclude']){
  let a={kind:'string'};
  for(let depth=0;depth<50;depth++)a=kind==='record'?{kind,fields:[{name:'nested',child:a}]}:kind==='array'||kind==='dictionary'?{kind,child:a,min:1,max:2}:specimen(kind,a);
  const valid=kind==='nullable'?'x':proposal(a);
  await run(a,[valid,corruptLeaf(valid),null],{seed:'depth50',index:kind});coverage.depth50++;
 }
 assert.equal(coverage.depth50,14);
});

test('emit coverage artifact and assert boundary corpus evidence',async()=>{
 const bounds=[{kind:'integer',min:-2,max:2},{kind:'string',min:1,max:2},{kind:'array',child:{kind:'string'},min:1,max:2},{kind:'dictionary',child:{kind:'string'},min:1,max:2}];
 for(const a of bounds){const values=a.kind==='integer'?[-3,-2,-1,1,2,3]:a.kind==='string'?['','x','xx','xxx']:a.kind==='array'?[[],['x'],['x','x'],['x','x','x']]:[{}, {a:'x'},{a:'x',b:'x'},{a:'x',b:'x',c:'x'}];await run(a,values,{seed:'bounds',index:a.kind});}
 coverage.boundaryCategories=['b-1','b','b+1','safe-integer','missing','null','extra-key','wrong-type','empty','unicode','overlap'];
 writeFileSync(new URL('./generated-coverage.json',import.meta.url),JSON.stringify(coverage,null,2)+'\n');
});

test('counterexample shrinker reduces nested recipes and inputs without hiding operational errors',()=>{
 const recipe=specimen('nullable',specimen('map',{kind:'string'}));
 const containsString=a=>a.kind==='string'||childNodes(a).some(containsString);
 const reduced=minimize(recipe,'xxxxx',(a,v)=>containsString(a)&&typeof v==='string'&&v.length>0);
 assert.deepEqual(reduced,{recipe:{kind:'string'},value:'x'});
 const marker=new Error('operational failure during shrinking');
 assert.throws(()=>minimize(recipe,'x',()=>{throw marker;}),e=>e===marker);
});

export { discrepancy };
