import test from 'node:test';
import assert from 'node:assert/strict';
import Ajv2020 from 'ajv/dist/2020.js';
import {s,emitted,evaluate} from './generated-api.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';

test('asserted UUID agrees with ordinary schema constraints without optional format checking',async()=>{
  let calls=0;
  const definition=s.assert_format(s.map(s.string(),text=>{calls++;return text;}),s.FormatAssertion$Uuid$const);
  const schema=emitted(definition);
  assert.equal(schema.allOf[1].then.format,'uuid');
  const ajv=new Ajv2020({strict:true,validateFormats:false});
  const validate=ajv.compile(schema),supplementary=await compileSupplementary(schema);
  const uuid='f81d4fae-7dec-11d0-a765-00a0c91e6bf6';
  const cases=[[uuid,true],[uuid.toUpperCase(),true],['00000000-0000-0000-0000-000000000000',true],['ffffffff-ffff-ffff-ffff-ffffffffffff',true],[uuid+'\n',false],[uuid+'\r',false],[uuid+'\u2028',false],['urn:uuid:'+uuid,false],[uuid.replaceAll('-',''),false],['g'+uuid.slice(1),false],[' '+uuid,false],[false,false],[null,false]];
  for(const [value,accepted] of cases){
    assert.equal(validate(value),accepted,JSON.stringify(value));
    assert.equal(supplementary(value).accepted,accepted,JSON.stringify(value));
    const before=calls;
    const actual=evaluate(definition,value);
    assert.equal(actual.accepted,accepted);
    assert.equal(calls-before,accepted?1:0);
    if(accepted)assert.equal(actual.value,value);
  }
});
