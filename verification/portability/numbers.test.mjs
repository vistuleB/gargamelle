import test from 'node:test';
import assert from 'node:assert/strict';
import {run} from './runner.mjs';

const bits = value => {
  const buffer = new ArrayBuffer(8), view = new DataView(buffer);
  view.setFloat64(0, value);
  return view.getBigUint64(0).toString();
};
test('Erlang number tokens match parsed binary64 values and JSON text', () => {
  const tokens = ['0', '-0', '1', '1.0', '-0.0', '1e-400', '-1e-400',
    '5e-324', '-5e-324', '1.7976931348623157e308', '1e400', '-1e400',
    '9007199254740993', '0.10000000000000001', '1.0000000000000001',
    '1e-6', '1e-7', '1e20', '1e21', '0e999999', '1e999999',
    '1e-999999', '1'+'0'.repeat(1000)+'e-1000', '9'.repeat(1000),
    '2.2250738585072012e-308', '2.4703282292062327e-324',
    '2.4703282292062328e-324'];
  const replies = run(tokens.map(token => ({token})));
  for (const [i, token] of tokens.entries()) {
    const value = JSON.parse(token), reply = replies[i];
    if (!Number.isFinite(value)) assert.equal(reply.error, 'nonfinite_number', token);
    else {
      assert.equal(reply.bits, bits(value), token);
      assert.equal(reply.text, JSON.stringify(value), token);
    }
  }
});

test('Erlang decimal conversion rounds a seeded token corpus like JSON.parse', () => {
  let state = 0x831725;
  const next = () => state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
  const tokens=[];
  for(let i=0;i<4000;i++) {
    const count=1+next()%90;
    let digits=String(1+next()%9);
    for(let j=1;j<count;j++) digits+=String(next()%10);
    const point=1+next()%count;
    const significand=digits.slice(0,point)+(point<count?'.'+digits.slice(point):'');
    tokens.push((next()%2?'-':'')+significand+'e'+(next()%801-400));
  }
  const replies=run(tokens.map(token=>({token})));
  for(const [i,token] of tokens.entries()) {
    const value=JSON.parse(token);
    if(!Number.isFinite(value)) assert.equal(replies[i].error,'nonfinite_number',token);
    else {
      assert.equal(replies[i].bits,bits(value),token);
      assert.equal(replies[i].text,JSON.stringify(value),token);
    }
  }
});

test('Erlang shortest number formatting matches Node across seeded binary64 values', () => {
  const values = [-0, 0, Number.MIN_VALUE, -Number.MIN_VALUE, Number.MAX_VALUE,
    1, -1, 9007199254740991, -9007199254740991,
    1e-6, 1e-7, 1e20, 1e21, 1000000000000000100];
  let state = 0x9639b674n;
  const mask = (1n << 64n) - 1n;
  const view = new DataView(new ArrayBuffer(8));
  for (let i=0;i<12000;i++) {
    state = (state * 6364136223846793005n + 1442695040888963407n) & mask;
    view.setBigUint64(0, state);
    const value = view.getFloat64(0);
    if (Number.isFinite(value)) values.push(value);
  }
  for(let exponent=-324;exponent<=308;exponent++) {
    const value=Number('1e'+exponent);
    values.push(value);
    if(value>0 && Number.isFinite(value)) {
      const raw=BigInt(bits(value));
      for(const delta of [-1n,1n]) {
        view.setBigUint64(0,raw+delta);
        const adjacent=view.getFloat64(0);
        if(Number.isFinite(adjacent)) values.push(adjacent,-adjacent);
      }
    }
  }
  const replies = run(values.map(value => ({bits: bits(value)})));
  for (const [i,value] of values.entries()) {
    assert.equal(replies[i].text, JSON.stringify(value), `bits=${bits(value)}`);
    assert.equal(replies[i].integer, Number.isInteger(value));
    assert.equal(replies[i].finite, true);
    if(Number.isSafeInteger(value)) {
      assert.equal(replies[i].conversion.integer_text,String(value));
      assert.equal(replies[i].conversion.float_text,JSON.stringify(value));
    } else assert.equal(replies[i].conversion,null);
  }
});
