import test from 'node:test';
import assert from 'node:assert/strict';
import {s,unwrap,toList,Some,None,Ok,emitted} from './generated-api.mjs';
import * as docs from '../build/dev/javascript/gargamelle/gargamelle/documentation.mjs';
import {compileOracle} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';
const inputs=values=>toList(values.map(v=>unwrap(s.parse(JSON.stringify(v)))));
test('checked documentation examples agree with validators and never decode',async()=>{
 let calls=0;const d=s.map(s.string(),()=>{calls++;throw new Error('decoder');});
 const schema=emitted(d),checks=[compileOracle(schema),await compileSupplementary(schema)];
 const values=['text','</article><script>alert(1)</script>','😀'];
 for(const v of values)for(const check of checks)assert.equal(check(v).accepted,true);
 const html=unwrap(docs.render_examples(d,'examples',inputs(values)));
 assert.match(html,/Checked examples/);assert.match(html,/&lt;script&gt;/);assert.equal(html.includes('<script>'),false);assert.equal(calls,0);
 assert.equal(html.split('</article>').length,2);
 assert.equal(unwrap(docs.render_examples(d,'empty',toList([]))),docs.render(d,'empty'));
});
test('all rejected examples retain index and paths and narrowing catches drift',()=>{
 const d=s.array(s.number());const result=docs.render_examples(d,'invalid',inputs([[1],['bad'],false,[0,'bad']]));
 assert.equal(result instanceof Ok,false);
 assert.deepEqual([...result[0]].map(e=>e.index),[1,2,3]);
 assert.deepEqual([...result[0]].map(e=>[...e.errors][0].path),['/0','','/1']);
 const value=inputs(['long']);assert.ok(docs.render_examples(s.string(),'old',value) instanceof Ok);
 assert.equal(docs.render_examples(unwrap(s.bounds(s.string(),None,new Some(2))),'new',value) instanceof Ok,false);
});
