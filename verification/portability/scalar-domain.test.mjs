import test from 'node:test';
import assert from 'node:assert/strict';
import {run} from './runner.mjs';

function scalarTree(value) {
  if(typeof value==='string')return value.isWellFormed();
  if(Array.isArray(value))return value.every(scalarTree);
  if(value && typeof value==='object')return Object.entries(value).every(([key,v])=>key.isWellFormed()&&scalarTree(v));
  return true;
}
test('native scalar admission agrees after escaped-surrogate parsing and duplicate resolution',()=>{
  const sources=[
    '"\\ud800"','"\\udfff"','"\\ud800\\ud800"','"\\udfff\\ud800"',
    '"\\ud800\\udc00"','"\\udbff\\udfff"','"\\ud800\\u0061"',
    '"\\ud800\\uXX00"','["\\ud800",]','{"x":"\\ud800"}x',
    '{"x":"\\ud800","x":1}','{"x":1,"x":"\\ud800"}',
    '{"x":{"y":"\\ud800"},"x":null}','{"\\ud800":1,"\\ud800":2}',
    '"\\\\ud800"','"\\ud800\\\\udc00"','{"x":"\\ud800","x":1,}',
  ];
  // Every surrogate unit, valid boundary pairs, mixed pairs and ordinary escapes.
  for(let unit=0xd800;unit<=0xdfff;unit++) {
    const escape='\\u'+unit.toString(16);
    sources.push('"'+escape+'"','{"x":"'+escape+'","x":0}','{"'+escape+'":0}');
    if(unit<=0xdbff) sources.push('"'+escape+'\\u'+(0xdc00+unit-0xd800).toString(16)+'"');
  }
  let state=0x51a7cafe;
  const next=()=>state=(Math.imul(state,1664525)+1013904223)>>>0;
  for(let i=0;i<1500;i++) {
    let text='';for(let j=0,n=next()%12;j<n;j++) text+='\\u'+(next()%65536).toString(16).padStart(4,'0');
    sources.push('"'+text+'"');
  }
  const replies=run(sources.map(source=>({source})));
  for(const [i,source] of sources.entries()) {
    let value;
    try{value=JSON.parse(source);}catch{assert.equal(replies[i].error,'syntax',source);continue;}
    if(!scalarTree(value)) assert.equal(replies[i].error,'non_scalar_string',source);
    else assert.deepEqual(JSON.parse(replies[i].text),value,source);
  }
});
