import test from 'node:test';
import assert from 'node:assert/strict';
import {run} from './runner.mjs';
const bits=value=>{const v=new DataView(new ArrayBuffer(8));v.setFloat64(0,value);return v.getBigUint64(0).toString();};

// Unicode-scalar domain; final unpaired surrogates are domain errors.
function canonical(value) {
  if(value===null || typeof value!=='object') return value;
  if(Array.isArray(value)) return value.map(canonical);
  const result=Object.create(null);
  for(const key of Object.keys(value).sort()) result[key]=canonical(value[key]);
  return result;
}
function hasNonfinite(value) {
  if(typeof value==='number') return !Number.isFinite(value);
  if(value && typeof value==='object') return Object.values(value).some(hasNonfinite);
  return false;
}

test('Erlang UTF-16 sorting and code-point lengths match JS on scalar strings',()=>{
  const strings=['', 'a', 'aa', 'é', '\u2028', '\ue000', '\u{10000}', '💜',
    '👩‍👩‍👧‍👧', 'a\u0301', '0', '10', '2', '\u0000', '\uffff', '\u{10ffff}'];
  const [reply]=run([{strings}]);
  assert.deepEqual(reply.sorted,[...strings].sort());
  assert.deepEqual(reply.lengths,strings.map(x=>[...x].length));
});

test('scalar JSON adapter preserves duplicate keys, hostile keys and canonical text',()=>{
  const sources=['null','true','false','[]','{}','""','[1,-0,1e20,1e21,1e-7,5e-324]',
    '{"a":1,"a":2}', '{"a":2,"a":1}', '{"__proto__":{"x":1},"constructor":false}',
    '{"10":1,"2":2,"00":3,"0":4,"4294967294":5,"4294967295":6}',
    '{"a":1e400}', '[1e400]', '1e400', '[1e400,]', '-0', '-0e0', '[1e400,2]', '{"a":1e400,"a":1}', '  1\r\n\t', '1 2', '{', '01', '-01', '+1', '--1', '1.', '1e', '1e+', '1e--1', '[1,]', '{"a":1,}', '[true false]', 'nullx', '\ufeffnull',
    '"\\ud800"', '"\\udc00"', '"\\ud83d\\udc9c"', '"\\u000b"'];
  const chars=['a','é','\u2028','\ue000','💜','\u{10000}','"','\\','\n','\t','\b','\f','\u0000','\u000b','/'];
  let state=0x38af52;
  const next=()=>state=(Math.imul(state,1664525)+1013904223)>>>0;
  for(let i=0;i<700;i++) {
    const obj=Object.create(null);
    for(let j=0;j<10;j++) obj[chars[next()%chars.length]+next()%15]=[
      chars[next()%chars.length], (next()/2**32-.5)*10**(next()%600-300),
      {missing:null,flag:next()%2===0}, [[],{}],
    ];
    sources.push(JSON.stringify(obj));
  }
  for(let code=0;code<32;code++) {
    sources.push(JSON.stringify(String.fromCharCode(code)));
    sources.push('"'+String.fromCharCode(code)+'"');
  }
  const valid=JSON.stringify({a:[1,false,null,'text'],b:{'💜':'é'}});
  const units=[...valid];
  for(let index=0;index<units.length;index++) {
    sources.push(units.slice(0,index).join(''));
    sources.push(units.slice(0,index).concat(units.slice(index+1)).join(''));
  }
  const replies=run(sources.map(source=>({source})));
  for(const [i,source] of sources.entries()) {
    const reply=replies[i];
    // Explicitly retain this incompatibility until the admitted domain is decided.
    if(source==='"\\ud800"' || source==='"\\udc00"') {
      assert.equal(reply.error,'non_scalar_string');
      continue;
    }
    let value;
    try {value=JSON.parse(source);} catch {assert.equal(reply.error,'syntax',source);continue;}
    if(hasNonfinite(value)) assert.equal(reply.error,'nonfinite_number',source);
    else {
      assert.equal(reply.text,JSON.stringify(canonical(value)),source);
      if(typeof value==='number') assert.equal(reply.bits,bits(value),source);
    }
  }
});
