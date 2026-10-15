import test from 'node:test';
import assert from 'node:assert/strict';
import {s,unwrap} from './generated-api.mjs';
import {compileOracle} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';

test('anything agrees with independent schema validators for every admitted JSON kind',async()=>{
  const named=unwrap(s.named('metadata',s.anything()));
  const definitions=[s.anything(),s.description(s.anything(),'arbitrary admitted JSON'),named,s.array(s.anything()),s.dictionary(named)];
  const values=[null,true,false,0,1.25,-0,Number.MAX_VALUE,'💜',[],{},[1,null,{nested:[true]}],JSON.parse('{"__proto__":"safe"}')];
  for(const definition of definitions){
    const schema=JSON.parse(s.schema_string(definition,s.JsonLayout$Compact$const));
    const oracles=[compileOracle(schema),await compileSupplementary(schema)];
    for(const value of values){
      const json=unwrap(s.parse(JSON.stringify(value))),accepted=s.validate(definition,json).isOk();
      for(const oracle of oracles)assert.equal(oracle(value).accepted,accepted);
      if(definition===definitions[0])assert.equal(unwrap(s.decode(definition,json)),json);
    }
  }
});

test('anything does not widen JSON admission or disguise structural rejection',()=>{
  for(const text of ['NaN','Infinity','1e999','"\\ud800"','{"\\udfff":1}'])assert.equal(s.parse(text).isOk(),false);
  const definition=s.array(s.anything());
  const json=unwrap(s.parse('{"x":true}'));
  const errors=s.validate(definition,json);
  assert.equal(errors.isOk(),false);assert.equal(errors[0].head.path,'');
});
