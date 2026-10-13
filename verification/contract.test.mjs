import * as b from '../build/dev/javascript/gargamelle/gargamelle/boundary.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {s, Ok, toList, unwrap} from './generated-api.mjs';
import {Error as GleamError} from '../build/dev/javascript/gargamelle/gleam.mjs';

test('semantic callback exceptions remain operational and stop subsequent callbacks',()=>{
  const failure=new Error('requirement failed operationally');
  const events=[];
  const definition=s.map(s.text(),text=>{events.push('decode');return text;});
  let contract=s.require(s.contract(definition),'Reject',()=>{events.push('reject');return new GleamError(toList([new s.Violation('','rejected')]));});
  contract=s.require(contract,'Throw',()=>{events.push('throw');throw failure;});
  contract=s.require(contract,'Later',()=>{events.push('later');return new Ok(undefined);});
  const receiver=b.json_boundary(contract,()=>events.push('handler'));
  assert.throws(()=>b.forward_json(receiver,unwrap(s.parse('"Brainy"'))),error=>error===failure);
  assert.deepEqual(events,['decode','reject','throw']);
});

test('verification retains the authoritative contract and discards decoded data',()=>{
  let conversions=0,checks=0;
  const definition=s.map(s.text(),text=>{conversions++;return {text};});
  const contract=s.require(s.contract(definition),'Nonempty',data=>{
    checks++;assert.equal(data.text,'Brainy');return new Ok(undefined);
  });
  const json=unwrap(s.parse('"Brainy"'));
  const verified=unwrap(s.verify(contract,json));
  assert.equal(s.verified_contract(verified),contract);
  assert.equal(s.verified_json(verified),json);
  assert.equal(conversions,1);
  assert.equal(checks,1);
  assert.deepEqual([...s.contract_requirements(contract)],['Nonempty']);
});
