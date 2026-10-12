import test from 'node:test';
import assert from 'node:assert/strict';
import {s,unwrap,toList,emitted,evaluate} from './generated-api.mjs';
import * as docs from '../build/dev/javascript/gargamelle/gargamelle/documentation.mjs';
import {compileOracle} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';

test('alternating object modifiers retain every conjunction across intervening wrappers',async()=>{
  const dependency=(d,key,required)=>unwrap(s.dependent_required(d,key,toList(required)));
  const keys=(d,k)=>unwrap(s.property_names(d,k));
  const prefix=unwrap(s.pattern(s.text(),'^a'));
  const cases=[
    [dependency(keys(dependency(s.dictionary(s.text()),'a',['b']),s.text()),'c',['d']),
      [[{},true],[{a:'x'},false],[{c:'x'},false],[{a:'x',b:'x'},true],[{a:'x',b:'x',c:'x'},false],[{a:'x',b:'x',c:'x',d:'x'},true]]],
    [keys(dependency(keys(s.dictionary(s.text()),prefix),'a',[]),s.text()),
      [[{},true],[{z:'x'},false],[{a:'x'},true]]],
    [dependency(keys(dependency(s.dictionary(s.text()),'a',['b']),s.text()),'a',['c']),
      [[{a:'x',b:'x'},false],[{a:'x',c:'x'},false],[{a:'x',b:'x',c:'x'},true]]],
  ];
  // Existing allOf clauses must survive both kinds of keyword collision.
  const base=dependency(keys(s.dictionary(s.text()),prefix),'a',['ab']);
  const conditional=s.if_then(base,s.dictionary(s.text()),dependency(s.dictionary(s.text()),'ab',['ac']));
  const composed=dependency(keys(dependency(keys(conditional,s.text()),'a',['ad']),prefix),'a',['ae']);
  cases.push([composed,[[{},true],[{z:'x'},false],[{a:'x',ad:'x',ae:'x'},false],[{a:'x',ab:'x',ad:'x',ae:'x'},false],[{a:'x',ab:'x',ac:'x',ad:'x'},false],[{a:'x',ab:'x',ac:'x',ad:'x',ae:'x'},true]]]);
  for(const [definition,values] of cases){
    let calls=0;
    const mapped=s.map(definition,value=>{calls++;return value;});
    const schema=emitted(mapped), checks=[compileOracle(schema),await compileSupplementary(schema)];
    for(const [value,accepted] of values){
      assert.equal(s.validate(mapped,unwrap(s.parse(JSON.stringify(value)))).isOk(),accepted,JSON.stringify(value));
      for(const check of checks)assert.equal(check(value).accepted,accepted,JSON.stringify({value,schema}));
      assert.equal(calls,0);
    }
    for(const [value,accepted] of values)assert.equal(evaluate(mapped,value).accepted,accepted);
    assert.equal(calls,values.filter(([,accepted])=>accepted).length);
  }
});

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
