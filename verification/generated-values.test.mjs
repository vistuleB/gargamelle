import test from 'node:test';
import assert from 'node:assert/strict';
import { build,evaluate,emitted,s,unwrap,toList,Some,None,Ok } from './generated-api.mjs';
const success=(recipe,input,expected)=>assert.deepEqual(evaluate(build(recipe),input),{accepted:true,value:expected});

test('hand-authored decoded values cover every primitive and composition',()=>{
 success({kind:'boolean'},false,false);success({kind:'null'},null,null);
 success({kind:'string'},' e\u0301😀\0 ',' e\u0301😀\0 ');
 success({kind:'integer'},Number.MAX_SAFE_INTEGER,Number.MAX_SAFE_INTEGER);
 // Contract treats -0 and 0 as equivalent; JSON.stringify input transport yields 0.
 success({kind:'integer'},-0,0);
 success({kind:'enum',values:['b','a']},'a','a');
 for(const value of [null,false,true,0,-1,''])success({kind:'constant',value},value,value);
 success({kind:'array',child:{kind:'string'}},['b','a','b'],['b','a','b']);
 const dictionary=JSON.parse('{"__proto__":"p","constructor":"c","toString":"t","":"empty","2":"two","10":"ten"}');
 success({kind:'dictionary',child:{kind:'string'}},dictionary,dictionary);
 success({kind:'nullable',child:{kind:'string'}},null,{none:true});
 success({kind:'nullable',child:{kind:'string'}},'x',{some:'x'});
 success({kind:'nullable',child:{kind:'nullable',child:{kind:'string'}}},'x',{some:{some:'x'}});
 success({kind:'nullable',child:{kind:'one',children:[{kind:'null'},{kind:'null'}]}},null,{none:true});
 success({kind:'any',children:[{kind:'map',child:{kind:'string'}},{kind:'string'}]},'x',{mapped:'x'});
 success({kind:'one',children:[{kind:'boolean'},{kind:'map',child:{kind:'string'}}]},'x',{mapped:'x'});
 success({kind:'description',child:{kind:'title',child:{kind:'string'}}},'x','x');
 success({kind:'map',child:{kind:'string'}},'x',{mapped:'x'});
});

test('record presence/defaults and variant payloads have explicit independent outputs',()=>{
 const recipe={kind:'record',fields:[{name:'required',child:{kind:'string'}},{name:'optional',child:{kind:'nullable',child:{kind:'string'}},presence:'optional'},{name:'default',child:{kind:'map',child:{kind:'string'}},presence:'defaulted',default:'fallback'}]};
 success(recipe,{required:'x'},{required:'x',optional:{none:true},default:{mapped:'fallback'}});
 success(recipe,{optional:null,required:'x'},{required:'x',optional:{some:{none:true}},default:{mapped:'fallback'}});
 success(recipe,{default:'given',optional:'y',required:'x'},{required:'x',optional:{some:{some:'y'}},default:{mapped:'given'}});
 assert.equal(evaluate(build(recipe),{required:'x',default:null}).accepted,false);
 const tagged={kind:'tagged',tag:'kind',branches:[{tag:'a',open:true,fields:[{name:'value',child:{kind:'string'}}]},{tag:'b',fields:[]}]};
 success(tagged,{kind:'a',value:'x',ignored:7},{tag:'a',payload:{value:'x'}});
 success(tagged,{kind:'b'},{tag:'b',payload:{}});
});

test('error locations preserve JSON Pointer escaping and union branch diagnostics',()=>{
 const record={kind:'record',fields:[{name:'a/~',child:{kind:'array',child:{kind:'string'}}}]};
 let e=[...evaluate(build(record),{'a/~':[false]}).value][0];assert.equal(e.path,'/a~1~0/0');assert.equal(e.category,'string_type');
 e=[...evaluate(build(record),{}).value][0];assert.equal(e.path,'');assert.equal(e.missing_key[0],'a/~');
 e=[...evaluate(build(record),{'a/~':[],'~/':1}).value][0];assert.equal(e.path,'/~0~1');assert.equal(e.category,'extra_key');
 const union=build({kind:'one',children:[{kind:'string'},{kind:'boolean'}]});
 e=[...evaluate(union,7).value][0];assert.equal(e.category,'union_no_match');assert.equal(e.path,'');assert.deepEqual([...e.branches].map(x=>x[0]),[0,1]);
 assert.deepEqual([...e.branches].flatMap(x=>[...x[1]].map(y=>y.path)),['','']);
 e=[...evaluate(build({kind:'one',children:[{kind:'string'},{kind:'string'}]}),'x').value][0];assert.equal(e.category,'one_of_ambiguous');assert.deepEqual([...e.matches],[0,1]);
});

test('annotations, defaults and number-like property names retain canonical structure',()=>{
 const d=build({kind:'description',value:'outer',child:{kind:'description',value:'inner',child:{kind:'title',value:'title',child:{kind:'record',fields:[{name:'10',child:{kind:'string'}},{name:'2',child:{kind:'string'}}]}}}});
 assert.deepEqual(emitted(d).required,['10','2']);assert.deepEqual(Object.keys(emitted(d).properties),['2','10']);assert.equal(emitted(d).description,'outer');assert.equal(emitted(d).title,'title');
 const value=JSON.parse('{"__proto__":"x","constructor":"y","toString":"z","10":"ten","2":"two"}');
 const recipe={kind:'record',fields:[{name:'defaults',presence:'defaulted',default:value,child:{kind:'dictionary',child:{kind:'string'}}}]};
 const definition=build(recipe);assert.deepEqual(emitted(definition).properties.defaults.default,value);success(recipe,{}, {defaults:value});
 const text=s.schema_string(definition);assert.equal(text,s.schema_string(definition));assert.equal(Object.getPrototypeOf(value),Object.prototype);
});

test('callback instrumentation sees only actual decoded values, no discovery/default validation calls',()=>{
 let calls=[];
 const child=s.map(s.text(),x=>{calls.push(['map',x]);return x.toUpperCase();});
 let record=s.record(x=>{calls.push(['record',x]);return x;});
 record=unwrap(s.defaulted(record,'a',child,unwrap(s.parse('"fallback"'))));
 const d=s.finish(record,s.Policy$Closed$const);
 assert.deepEqual(calls,[]);s.schema_string(d);s.validate(d,unwrap(s.parse('{}')));assert.deepEqual(calls,[]);
 const result=s.decode(d,unwrap(s.parse('{}')));assert.ok(result instanceof Ok);assert.equal(result[0],'FALLBACK');assert.deepEqual(calls,[['map','fallback'],['record','FALLBACK']]);
 calls=[];const overlap=unwrap(s.one_of(toList([child,child])));assert.equal(s.decode(overlap,unwrap(s.parse('"x"'))) instanceof Ok,false);assert.deepEqual(calls,[]);
});

test('construction failure matrix rejects invalid sizes, bounds, defaults, enums and branches',()=>{
 for(const n of [-1,0.5,Infinity,NaN,Number.MAX_SAFE_INTEGER+1])for(const d of [s.text(),s.array(s.text()),s.dictionary(s.text())])assert.equal(s.bounds(d,new Some(n),None) instanceof Ok,false);
 for(const n of [0.5,Infinity,NaN,Number.MAX_SAFE_INTEGER+1,-Number.MAX_SAFE_INTEGER-1])assert.equal(s.bounds(s.safe_integer(),new Some(n),None) instanceof Ok,false);
 for(const d of [s.text(),s.safe_integer(),s.array(s.text()),s.dictionary(s.text())])assert.equal(s.bounds(d,new Some(3),new Some(2)) instanceof Ok,false);
 const bounded=unwrap(s.bounds(s.text(),new Some(3),None));assert.equal(s.bounds(bounded,None,new Some(2)) instanceof Ok,false);
 assert.equal(s.pattern(s.text(),'[') instanceof Ok,false);
 for(const values of [[],['a','a']])assert.equal(s.string_enum(toList(values)) instanceof Ok,false);
 for(const union of [s.any_of,s.one_of])assert.equal(union(toList([])) instanceof Ok,false);
 assert.equal(s.tagged('kind',toList([])) instanceof Ok,false);
 assert.equal(s.tagged('kind',toList([s.variant('a',s.record(null),s.Policy$Closed$const),s.variant('a',s.record(null),s.Policy$Closed$const)])) instanceof Ok,false);
 let r=unwrap(s.required(s.record(x=>x),'kind',s.text()));assert.equal(s.tagged('kind',toList([s.variant('a',r,s.Policy$Closed$const)])) instanceof Ok,false);
 r=unwrap(s.required(s.record(x=>y=>[x,y]),'x',s.text()));assert.equal(s.required(r,'x',s.text()) instanceof Ok,false);assert.equal(s.optional(r,'x',s.text()) instanceof Ok,false);
 assert.equal(s.defaulted(s.record(x=>x),'x',s.text(),unwrap(s.parse('null'))) instanceof Ok,false);
});

test('safe-integer endpoints and repeated bound intersections are explicit',()=>{
 const d=build({kind:'integer'});
 for(const value of [Number.MIN_SAFE_INTEGER,Number.MIN_SAFE_INTEGER+1,Number.MAX_SAFE_INTEGER-1,Number.MAX_SAFE_INTEGER])assert.deepEqual(evaluate(d,value),{accepted:true,value});
 for(const value of [Number.MIN_SAFE_INTEGER-1,Number.MAX_SAFE_INTEGER+1,-0.5,0.5])assert.equal(evaluate(d,value).accepted,false);
 let bounded=unwrap(s.bounds(s.safe_integer(),new Some(-5),new Some(5)));
 bounded=unwrap(s.bounds(bounded,new Some(-2),new Some(3)));
 bounded=unwrap(s.bounds(bounded,new Some(-4),new Some(4)));
 assert.equal(emitted(bounded).minimum,-2);assert.equal(emitted(bounded).maximum,3);
 for(const value of [-3,-2,-1,2,3,4])assert.equal(evaluate(bounded,value).accepted,value>=-2&&value<=3);
});
