import test from 'node:test';
import assert from 'node:assert/strict';
import {s,unwrap,emitted,evaluate} from './generated-api.mjs';
import {compileOracle} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';

test('safe-integer multipleOf agrees with exact integer remainders and both oracles',async()=>{
  for(const divisor of [1,2,3,7,31,100,9007199254740991]){
    const definition=unwrap(s.integer_multiple_of(s.safe_integer(),divisor));
    const schema=emitted(definition);
    assert.equal(schema.multipleOf,divisor);
    const checks=[compileOracle(schema),await compileSupplementary(schema)];
    for(const value of [...Array.from({length:513},(_,i)=>i-256),9007199254740991,9007199254740990,-9007199254740991,0.5,'3']){
      const accepted=typeof value==='number'&&Number.isSafeInteger(value)&&BigInt(value)%BigInt(divisor)===0n;
      for(const check of checks)assert.equal(check(value).accepted,accepted,`${value} / ${divisor}`);
      assert.equal(evaluate(definition,value).accepted,accepted,`${value} / ${divisor}`);
    }
  }
  const intersection=unwrap(s.integer_multiple_of(unwrap(s.integer_multiple_of(s.safe_integer(),2)),3));
  const checks=[compileOracle(emitted(intersection)),await compileSupplementary(emitted(intersection))];
  for(const value of [-12,-3,0,6,10,12]){
    for(const check of checks)assert.equal(check(value).accepted,value%6===0);
    assert.equal(evaluate(intersection,value).accepted,value%6===0);
  }
});
