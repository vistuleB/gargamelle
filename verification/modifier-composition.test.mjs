import test from 'node:test';
import assert from 'node:assert/strict';
import Ajv2020 from 'ajv/dist/2020.js';
import {s,Ok,unwrap,toList,Some,None,emitted} from './generated-api.mjs';
import {oracleOptions} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';

// Metadata and conditional schema fragments can intentionally omit a local
// primitive type. Disable only strictTypes lint and optional format assertions.
const options={...oracleOptions,strictTypes:false,validateFormats:false};
async function check(def,values,expected,label){
 const schema=emitted(def),ajv=new Ajv2020(options);
 assert.equal(ajv.validateSchema(schema),true);
 const validate=ajv.compile(schema),hyperjump=await compileSupplementary(schema);
 for(const [i,value] of values.entries()){
  const json=unwrap(s.parse(JSON.stringify(value)));
  assert.equal(s.validate(def,json).isOk(),expected[i],`${label}: validate ${JSON.stringify(value)}`);
  assert.equal(s.decode(def,json).isOk(),expected[i],`${label}: decode ${JSON.stringify(value)}`);
  assert.equal(validate(value),expected[i],`${label}: Ajv ${JSON.stringify(value)}`);
  assert.equal(hyperjump(value).accepted,expected[i],`${label}: Hyperjump ${JSON.stringify(value)}`);
 }
 return schema;
}
const wrap=(d,name)=>unwrap(s.named(name,s.title(s.description(s.examples(s.default_annotation(s.format_annotation(d,'custom'),unwrap(s.parse('null'))),toList([unwrap(s.parse('false'))])),'description'),'title')));
const cases=[
 {name:'text bounds',base:()=>s.string(),modify:d=>unwrap(s.bounds(d,new Some(2),new Some(4))),values:['','a','ab','abcd','abcde',false],expected:[false,false,true,true,false,false]},
 {name:'text pattern',base:()=>s.string(),modify:d=>unwrap(s.pattern(d,'^a+$')),values:['','a','aa','ab',null],expected:[false,true,true,false,false]},
 {name:'integer bounds',base:()=>s.safe_integer(),modify:d=>unwrap(s.bounds(d,new Some(2),new Some(4))),values:[1,2,3,4,5,2.5,'3'],expected:[false,true,true,true,false,false,false]},
 {name:'number bounds',base:()=>s.number(),modify:d=>unwrap(s.number_bounds(d,new Some(new s.Exclusive(1)),new Some(new s.Inclusive(2)))),values:[1,1.5,2,2.5,'1.5'],expected:[false,true,true,false,false]},
 {name:'integer multiples',base:()=>s.safe_integer(),modify:d=>unwrap(s.integer_multiple_of(d,3)),values:[0,3,-3,4,1.5,'3'],expected:[true,true,true,false,false,false]},
 {name:'array bounds',base:()=>s.array(s.string()),modify:d=>unwrap(s.bounds(d,new Some(1),new Some(2))),values:[[],['a'],['a','b'],['a','b','c'],[false],{}],expected:[false,true,true,false,false,false]},
 {name:'dictionary bounds',base:()=>s.dictionary(s.string()),modify:d=>unwrap(s.bounds(d,new Some(1),new Some(2))),values:[{},{a:'x'},{a:'x',b:'y'},{a:'x',b:'y',c:'z'},{a:false},[]],expected:[false,true,true,false,false,false]},
 {name:'unique items',base:()=>s.array(s.string()),modify:d=>unwrap(s.unique_items(d)),values:[[],['a'],['a','b'],['a','a'],[false],{}],expected:[true,true,true,false,false,false]},
 {name:'contains',base:()=>s.array(s.string()),modify:d=>unwrap(s.contains(d,s.string_constant('a'),1,None)),values:[[],['a'],['b'],['a','b'],[false]],expected:[false,true,false,true,false]},
 {name:'property names',base:()=>s.dictionary(s.string()),modify:d=>unwrap(s.property_names(d,unwrap(s.pattern(s.string(),'^a')))),values:[{},{a:'x'},{b:'x'},{a:false},[]],expected:[true,true,false,false,false]},
 {name:'dependencies',base:()=>s.dictionary(s.string()),modify:d=>unwrap(s.dependent_required(d,'a',toList(['b']))),values:[{},{a:'x'},{b:'x'},{a:'x',b:'x'},{a:null}],expected:[true,false,true,true,false]},
];

test('named and every annotation preserve modifier support, acceptance and mapped output',async()=>{
 for(const [i,c] of cases.entries()){
  let calls=0;
  const mapped=d=>s.map(d,x=>{calls++;return x;});
  const before=wrap(c.modify(mapped(c.base())),`before-${i}`);
  const after=c.modify(wrap(mapped(c.base()),`after-${i}`));
  for(const [label,d] of [['before',before],['after',after]]){
   assert.equal(calls,0);
   s.schema_string(d,s.JsonLayout$Compact$const);assert.equal(calls,0);
   for(const value of c.values){const json=unwrap(s.parse(JSON.stringify(value)));s.validate(d,json);assert.equal(calls,0);}
   await check(d,c.values,c.expected,c.name+' '+label);
   assert.equal(calls,c.expected.filter(Boolean).length,c.name+' map invocation count');
   calls=0;
  }
  for(const [j,value] of c.values.entries())if(c.expected[j]){
   const json=unwrap(s.parse(JSON.stringify(value)));
   assert.deepEqual(unwrap(s.decode(after,json)),unwrap(s.decode(before,json)),c.name);
  }
 }
});

test('same-input assertions compose without running auxiliary converters',async()=>{
 const forbidden=s.map(s.string_constant('bad'),()=>{throw Error('forbidden converter ran');});
 const consequence=s.map(unwrap(s.bounds(s.string(),new Some(2),None)),()=>{throw Error('consequence converter ran');});
 const condition=s.map(s.string(),()=>{throw Error('condition converter ran');});
 let text=s.if_then(s.exclude(wrap(s.string(),'constrained-text'),forbidden),condition,consequence);
 text=unwrap(s.pattern(unwrap(s.bounds(text,None,new Some(3))),'^[a-z]+$'));
 await check(text,['a','ab','abc','abcd','bad','AB',false],[false,true,true,false,false,false,false],'asserted text');
 let integer=s.exclude(wrap(s.safe_integer(),'constrained-int'),unwrap(s.integer_constant(6)));
 integer=unwrap(s.integer_multiple_of(integer,2));
 integer=wrap(integer,'constrained-multiples');
 integer=unwrap(s.integer_multiple_of(integer,3));
 integer=unwrap(s.bounds(integer,new Some(0),new Some(12)));
 await check(integer,[-6,0,2,3,6,12,18],[false,true,false,false,false,true,false],'asserted integer');
 const number=unwrap(s.number_bounds(s.if_then(s.number(),s.number(),s.number()),new Some(new s.Inclusive(0)),new Some(new s.Exclusive(1))));
 await check(number,[-1,0,0.5,1],[false,true,true,false],'asserted number');
});

test('separated array modifiers preserve membership, uniqueness, size and prior conjunctions',async()=>{
 let d=unwrap(s.contains(s.array(s.safe_integer()),unwrap(s.integer_constant(1)),1,None));
 d=unwrap(s.unique_items(d));
 d=s.exclude(d,s.map(s.array(unwrap(s.integer_constant(1))),()=>{throw Error('auxiliary array conversion');}));
 d=unwrap(s.contains(d,unwrap(s.integer_constant(2)),1,None));
 d=unwrap(s.contains(d,unwrap(s.integer_constant(3)),1,None));
 d=unwrap(s.bounds(wrap(d,'constrained-array'),new Some(3),new Some(4)));
 const schema=await check(d,[[1,2,3],[1,2,3,4],[2,3,4],[1,3,4],[1,2,4],[1,2,3,3],[1,2],[1,2,3,4,5]],
  [true,true,false,false,false,false,false,false],'separated arrays');
 assert.ok(schema.$defs['constrained-array']);
 const matching=x=>unwrap(s.contains(s.array(s.safe_integer()),unwrap(s.integer_constant(x)),1,None));
 let conditional=s.if_then(s.array(s.safe_integer()),s.map(matching(1),()=>{throw Error('condition conversion');}),s.map(matching(2),()=>{throw Error('consequence conversion');}));
 conditional=unwrap(s.contains(conditional,unwrap(s.integer_constant(3)),1,None));
 conditional=unwrap(s.unique_items(conditional));
 conditional=unwrap(s.bounds(conditional,new Some(1),new Some(3)));
 await check(conditional,[[3],[1,2,3],[1,3],[2],[3,3]], [true,true,false,false,false],'conditional arrays');
 let counted=unwrap(s.contains(s.array(s.string()),unwrap(s.pattern(s.string(),'^a')),1,new Some(1)));
 counted=unwrap(s.unique_items(counted));
 counted=unwrap(s.contains(counted,unwrap(s.pattern(s.string(),'^b')),1,None));
 await check(counted,[['a','b'],['a','ab','b'],['b'],['a'],['a','c','b'],[]],
  [true,false,false,false,true,false],'separated contains upper limits');


});

test('unsupported shapes and references produce construction errors rather than distribution',()=>{
 const wrong=[s.nullable(s.string()),unwrap(s.any_of(toList([s.string(),s.boolean()]))),s.string_constant('a'),s.anything()];
 for(const d of wrong){assert.equal(s.bounds(d,None,new Some(2)).isOk(),false);assert.equal(s.pattern(d,'a').isOk(),false);}
 const tree=unwrap(s.recursive('tree',self=>new Ok(s.array(self))));
 assert.equal(s.bounds(tree,None,new Some(2)).isOk(),false);
 assert.equal(s.contains(tree,s.anything(),1,None).isOk(),false);
 assert.equal(s.unique_items(tree).isOk(),false);
 const referenceResult=s.recursive('reference',self=>s.bounds(self,None,new Some(2)));
 assert.equal(referenceResult.isOk(),false);
 const tuple=s.finish_tuple(s.element(s.tuple(x=>x),s.string()));
 assert.equal(s.unique_items(tuple).isOk(),false);assert.equal(s.bounds(tuple,None,new Some(2)).isOk(),false);
 assert.equal(s.property_names(s.nullable(s.dictionary(s.string())),s.string()).isOk(),false);
 assert.equal(s.dependent_required(s.array(s.string()),'a',toList(['b'])).isOk(),false);
 assert.equal(s.number_bounds(s.map(s.string(),()=>1.0),None,new Some(new s.Inclusive(2))).isOk(),false);
 assert.equal(s.pattern(s.map(s.number(),()=>''),'a').isOk(),false);
});

test('shape-rewriting modifiers preserve names and reject conflicting reuse explicitly',()=>{
 const original=unwrap(s.named('shared',s.string()));
 const changed=unwrap(s.bounds(original,new Some(2),None));
 assert.equal(emitted(changed).$defs.shared.minLength,2);
 const combined=unwrap(s.any_of(toList([original,changed])));
 assert.throws(()=>s.schema_string(combined,s.JsonLayout$Compact$const),/Conflicting named schema definitions/);
 assert.throws(()=>s.validate(combined,unwrap(s.parse('"ab"'))),/conflicting names/);
 assert.equal(s.bounds(changed,None,new Some(1)).isOk(),false);
 // Assertion-only modifiers remain local to a use of a shared named definition.
 const sharedArray=unwrap(s.named('shared-array',s.array(s.string())));
 const unique=unwrap(s.unique_items(sharedArray));
 const useBoth=unwrap(s.any_of(toList([sharedArray,unique])));
 assert.equal(Object.keys(emitted(useBoth).$defs).length,1);
});
