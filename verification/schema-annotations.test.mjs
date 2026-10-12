import test from 'node:test';
import assert from 'node:assert/strict';
import {s,unwrap,toList,emitted} from './generated-api.mjs';
import * as docs from '../build/dev/javascript/gargamelle/gargamelle/documentation.mjs';
import {compileOracle} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';
import Ajv2020 from 'ajv/dist/2020.js';

test('schema examples are annotations, including invalid samples, and never convert',async()=>{
  let calls=0;
  const definition=s.examples(s.map(s.text(),()=>{calls++;throw new Error('must not convert');}),toList([unwrap(s.parse('false')),unwrap(s.parse('"<script>"'))]));
  const schema=emitted(definition);
  assert.deepEqual(schema.examples,[false,'<script>']);
  for(const check of [compileOracle(schema),await compileSupplementary(schema)]){
    assert.equal(check('Brainy').accepted,true);
    assert.equal(check(false).accepted,false);
  }
  const html=docs.render(definition,'examples');
  assert.match(html,/examples:/);
  assert.match(html,/&lt;script&gt;/);
  assert.equal(calls,0);
});

test('format uses annotation semantics with explicitly disabled oracle assertions',async()=>{
  for(const name of ['email','uuid','application-name']){
    const definition=s.format(s.text(),name);
    const schema=emitted(definition);
    const ajv=new Ajv2020({strict:true,validateFormats:false});
    assert.equal(ajv.validateSchema(schema),true);
    const validate=ajv.compile(schema);
    const supplementary=await compileSupplementary(schema);
    for(const [value,accepted] of [['not a format',true],[false,false]]){
      assert.equal(validate(value),accepted);
      assert.equal(supplementary(value).accepted,accepted);
      assert.equal(s.validate(definition,unwrap(s.parse(JSON.stringify(value)))).isOk(),accepted);
    }
    assert.match(docs.render(definition,'format'),/\(annotation\)/);
  }
  assert.throws(()=>s.format(s.text(),'\ud800'),/Unicode scalar/);
});

test('standalone default is unrestricted metadata and never inserts or converts',async()=>{
  let calls=0;
  const definition=s.default$(s.map(s.text(),()=>{calls++;throw new Error('must not convert');}),unwrap(s.parse('false')));
  const schema=emitted(definition);
  assert.equal(schema.default,false);
  for(const check of [compileOracle(schema),await compileSupplementary(schema)]){
    assert.equal(check('Brainy').accepted,true);
    assert.equal(check(false).accepted,false);
  }
  assert.match(docs.render(definition,'default'),/default: false/);
  assert.equal(calls,0);
});
