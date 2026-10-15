import assert from 'node:assert/strict';
import Ajv2020 from 'ajv/dist/2020.js';
import {oracleOptions} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';

export const compositionSeeds=[0x104,0x202012,0xc0111de,0x5eed];
const assertionKinds=['dependency','keys','conditional','exclude'];
const wrapperKinds=['title','description','examples','default','format','map','named'];
// Only independent assertions are commuted. Metadata and transformations are
// tested for unchanged acceptance, never for output/annotation commutativity.
const orderWhitelist=[['dependency','dependency'],['keys','keys'],['dependency','keys']];
const names=['a','b','c','d','z','aa'];
// `format` is metadata even on object definitions. Ajv's strictTypes lint
// forbids that placement; disable the lint and optional format assertions,
// retaining schema validation and every other oracle option.
const compositionOracleOptions={...oracleOptions,validateFormats:false,strictTypes:false};
function random(seed){let state=seed>>>0;return n=>{state=(Math.imul(state,1664525)+1013904223)>>>0;return state%n;};}
function inputs(){
  const values=[null,false,0,'a',[],{a:0},{a:null}];
  for(let mask=0;mask<64;mask++)values.push(Object.fromEntries(names.filter((_,i)=>mask&(1<<i)).map(k=>[k,'x'])));
  values.push({a:{a:'x',b:'x'},b:'x'},{a:{z:'x'},b:'x'});
  return values;
}
export async function runCompositionSuite({s,unwrap,toList},seeds=compositionSeeds){
  const values=inputs(),pairs=new Set(),separated=new Set(),wrappers=new Set();
  let snapshots=0,comparisons=0,monotonicChecks=0,metadataChecks=0,orderChecks=0,recursiveSequences=0,callbacks=0;
  const input=values.map(value=>unwrap(s.parse(JSON.stringify(value))));
  const presence=key=>s.finish(unwrap(s.required(s.record(x=>x),key,s.string())),s.RecordPolicy$Open$const);
  const apply=(base,step,id)=>{
    switch(step.kind){
      case 'dependency':return unwrap(s.dependent_required(base,step.key,toList(step.required)));
      case 'keys':return unwrap(s.property_names(base,s.map(unwrap(s.pattern(s.string(),step.pattern)),()=>{throw new Error('key converter ran');})));
      case 'conditional':return s.if_then(base,presence(step.key),unwrap(s.dependent_required(s.dictionary(s.string()),step.key,toList(step.required))));
      case 'exclude':return s.exclude(base,presence(step.key));
      case 'title':return s.title(base,'composition '+id);
      case 'description':return s.description(base,'bounded composition');
      case 'examples':return s.examples(base,toList([unwrap(s.parse('{"z":0}'))]));
      case 'default':return s.default_annotation(base,unwrap(s.parse('false')));
      case 'format':return s.format_annotation(base,'custom-composition');
      case 'map':return s.map(base,x=>{callbacks++;return x;});
      case 'named':return unwrap(s.named('composition-'+id,base));
      default:throw new Error('Unknown step '+step.kind);
    }
  };
  const snapshot=async(definition,label)=>{
    const schema=JSON.parse(s.schema_string(definition,s.JsonFormat$Compact$const));
    const ajv=new Ajv2020(compositionOracleOptions);
    assert.equal(ajv.validateSchema(schema),true);
    const validate=ajv.compile(schema);
    const checks=[value=>({accepted:validate(value)}),await compileSupplementary(schema)];
    const accepted=[];
    for(const [i,value] of values.entries()){
      const before=callbacks;
      const runtime=s.validate(definition,input[i]).isOk();
      assert.equal(callbacks,before,label+' validation invoked conversion');
      assert.equal(s.decode(definition,input[i]).isOk(),runtime,label+' decode/validate');
      for(const check of checks)assert.equal(check(value).accepted,runtime,JSON.stringify({label,value,schema}));
      accepted.push(runtime);comparisons++;
    }
    assert.ok(accepted.some(Boolean),label+' accidentally rejects everything');
    assert.ok(accepted.some(x=>!x),label+' lacks rejected inputs');
    snapshots++;return accepted;
  };
  const makeAssertion=(kind,pick)=>({kind,key:['a','b','c'][pick(3)],required:[['b'],['c'],['d']][pick(3)],pattern:['^[a-d]+$','^a|^b|^c|^d','^[a-z]{1,2}$'][pick(3)]});
  for(const seed of seeds){
    const pick=random(seed);
    for(let index=0;index<8;index++){
      // A directed prefix retains both audit reproductions and repeated triggers.
      const steps=index%2===0
        ? [{kind:'dependency',key:'a',required:['b']},{kind:'keys',pattern:'^[a-d]+$'},{kind:'dependency',key:'a',required:['c']}]
        : [{kind:'keys',pattern:'^[a-d]+$'},{kind:'dependency',key:'a',required:['b']},{kind:'keys',pattern:'^[a-z]{1,2}$'}];
      steps.push({kind:wrapperKinds[index%wrapperKinds.length]});
      while(steps.length<6+index%5){const kind=[...assertionKinds,...wrapperKinds][pick(11)];steps.push(assertionKinds.includes(kind)?makeAssertion(kind,pick):{kind});}
      let definition=s.dictionary(s.string());
      if(index===7){
        recursiveSequences++;
        definition=unwrap(s.recursive('sequence-tree-'+seed,self=>{
          let body=s.dictionary(self);
          for(const [i,step] of steps.entries())body=apply(body,step,'recursive-'+seed+'-'+i);
          return s.any_of(toList([s.map(s.string(),()=>null),s.map(body,()=>null)]));
        }));
        // Keep the top level an object, with recursive constraints on its values.
        definition=s.dictionary(definition);
      }
      let previous=await snapshot(definition,seed+'/'+index+'/base');
      for(const [i,step] of steps.entries()){
        if(i>0)pairs.add(steps[i-1].kind+' → '+step.kind);
        if(steps.slice(0,i-1).some(prior=>prior.kind===step.kind))separated.add(step.kind);
        if(wrapperKinds.includes(step.kind))wrappers.add(step.kind);
        definition=apply(definition,step,seed+'-'+index+'-'+i);
        const current=await snapshot(definition,seed+'/'+index+'/'+i+'/'+step.kind);
        for(let j=0;j<values.length;j++){
          assert.ok(!current[j]||previous[j],seed+'/'+index+'/'+i+' weakened acceptance: '+JSON.stringify(values[j]));monotonicChecks++;
          if(wrapperKinds.includes(step.kind)){assert.equal(current[j],previous[j],step.kind+' changed acceptance');metadataChecks++;}
        }
        previous=current;
      }
    }
    for(const [index,[first,second]] of orderWhitelist.entries()){
      const a=makeAssertion(first,pick),b=makeAssertion(second,pick);
      const forward=await snapshot(apply(apply(s.dictionary(s.string()),a,'order-a'),b,'order-b'),seed+'/order/'+index+'/forward');
      const reverse=await snapshot(apply(apply(s.dictionary(s.string()),b,'order-b'),a,'order-a'),seed+'/order/'+index+'/reverse');
      assert.deepEqual(forward,reverse,'Whitelisted order changed acceptance');orderChecks+=values.length;
    }
  }
  return {seeds,sequenceCount:seeds.length*8,recursiveSequences,snapshots,inputsPerSnapshot:values.length,comparisons,monotonicChecks,metadataChecks,orderChecks,orderWhitelist,oracleOptions:compositionOracleOptions,adjacentPairs:[...pairs].sort(),separatedRepetitions:[...separated].sort(),wrapperFamilies:[...wrappers].sort(),scope:'Bounded object-modifier sequences; not exhaustive constructor coverage'};
}
