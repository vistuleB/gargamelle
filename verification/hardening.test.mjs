import test from 'node:test';
import assert from 'node:assert/strict';
import {build,evaluateText,emitted} from './generated-api.mjs';
import {compileOracle} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';
import {classifySplit} from './oracle-classification.mjs';
import {reference} from './reference.mjs';
import {minimizeAsync} from './generated-shrink.mjs';

test('both validators and decoder consume exactly the same JSON text, including negative zero',async()=>{
 const d=build({kind:'integer'}),schema=emitted(d),checks=[compileOracle(schema),await compileSupplementary(schema)];
 for(const text of ['-0','0','1.0','-1','1.5','9007199254740992']){
  const v=JSON.parse(text),actual=evaluateText(d,text);
  for(const check of checks)assert.equal(actual.accepted,check(v).accepted,text);
  if(actual.accepted)assert.equal(actual.value===v,true);
 }
 assert.ok(Object.is(JSON.parse('-0'),-0));
});

test('oracle splits require a successful key-rename diagnosis',async()=>{
 const schema=emitted(build({kind:'record',fields:[{name:'__proto__',child:{kind:'string'}}]}));
 const v=JSON.parse('{"__proto__":"x"}'),a=compileOracle(schema)(v),h=(await compileSupplementary(schema))(v);
 assert.equal(classifySplit(schema,v,a,h),'ajv-declared-proto-key');
 assert.throws(()=>classifySplit({type:'string'},'x',{accepted:false},{accepted:true}),/Unclassified/);
 assert.equal(classifySplit(schema,{}, {accepted:true},{accepted:true}),null);
 assert.throws(()=>classifySplit(schema,v,{accepted:true},{accepted:false}),/survives key rename/);
});

test('independent reference has explicit branch-order, default, optional and nullable expectations',()=>{
 const a={kind:'record',fields:[{name:'x',presence:'defaulted',default:'abc',child:{kind:'map',child:{kind:'string'}}},{name:'y',presence:'optional',child:{kind:'nullable',child:{kind:'string'}}}]};
 assert.deepEqual(reference(a,{}),{accepted:true,value:{x:{mapped:'abc'},y:{none:true}}});
 assert.deepEqual(reference(a,{y:null}),{accepted:true,value:{x:{mapped:'abc'},y:{some:{none:true}}}});
 const branches=[{kind:'map',child:{kind:'string'}},{kind:'string'}];
 assert.deepEqual(reference({kind:'any',children:branches},'x'),{accepted:true,value:{mapped:'x'}});
 assert.deepEqual(reference({kind:'one',children:branches},'x'),{accepted:false});
});

test('async differential shrinking preserves failure and propagates operational exceptions',async()=>{
 const reduced=await minimizeAsync({kind:'map',child:{kind:'string'}},'abc',async(a,v)=>a.kind==='string'&&typeof v==='string'&&v.length>0);
 assert.deepEqual(reduced,{recipe:{kind:'string'},value:'a'});
 const marker=new Error('oracle crash');await assert.rejects(minimizeAsync({kind:'map',child:{kind:'string'}},'x',async()=>{throw marker;}),e=>e===marker);
});

test('one-code-point bounds accept astral characters and reject two code points',async()=>{
 const d=build({kind:'string',min:1,max:1}),schema=emitted(d),checks=[compileOracle(schema),await compileSupplementary(schema)];
 for(const [v,accepted] of [['😀',true],['😀a',false],['e\u0301',false],['',false]]){
  assert.equal(evaluateText(d,JSON.stringify(v)).accepted,accepted);
  for(const check of checks)assert.equal(check(v).accepted,accepted);
 }
});
