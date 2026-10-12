import test from 'node:test';
import assert from 'node:assert/strict';
import {s,unwrap,toList,emitted,evaluate} from './generated-api.mjs';
import * as docs from '../build/dev/javascript/gargamelle/gargamelle/documentation.mjs';
import {compileOracle} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';

test('dependentRequired uses original own-key presence and agrees with both schema oracles',async()=>{
  let calls=0;
  let definition=unwrap(s.dependent_required(s.map(s.dictionary(s.nullable(s.text())),x=>{calls++;return x;}),'token',toList(['expires_at','expires_at'])));
  definition=unwrap(s.dependent_required(definition,'token',toList(['token','issuer'])));
  const schema=emitted(definition);
  assert.deepEqual(schema.dependentRequired,{token:['expires_at','token','issuer']});
  const checks=[compileOracle(schema),await compileSupplementary(schema)];
  for(const [value,accepted] of [[{},true],[{issuer:null},true],[{token:null},false],[{token:'x',expires_at:null},false],[{token:null,expires_at:null,issuer:null},true],[false,false]]){
    for(const check of checks)assert.equal(check(value).accepted,accepted,JSON.stringify(value));
    assert.equal(s.validate(definition,unwrap(s.parse(JSON.stringify(value)))).isOk(),accepted);
  }
  assert.equal(calls,0);
  assert.equal(evaluate(definition,{token:null}).accepted,false);
  assert.equal(calls,0);
  assert.equal(evaluate(definition,{}).accepted,true);
  assert.equal(calls,1);
  assert.match(docs.render(definition,'dependencies'),/is present, require/);
});

test('dependentRequired composes with named schemas, key constraints and hostile keys',async()=>{
  let definition=unwrap(s.named('flags',s.dictionary(s.boolean())));
  definition=unwrap(s.dependent_required(definition,'__proto__',toList(['a/~'])));
  definition=unwrap(s.property_names(definition,s.text()));
  const checks=[compileOracle(emitted(definition)),await compileSupplementary(emitted(definition))];
  for(const [source,accepted] of [['{}',true],['{"__proto__":true}',false],['{"__proto__":true,"a/~":false}',true]]){
    for(const check of checks)assert.equal(check(JSON.parse(source)).accepted,accepted);
    assert.equal(s.validate(definition,unwrap(s.parse(source))).isOk(),accepted);
  }
  assert.equal(s.dependent_required(s.dictionary(s.text()),'\ud800',toList([])).isOk(),false);
  assert.equal(s.dependent_required(s.dictionary(s.text()),'a',toList(['\ud800'])).isOk(),false);
});
