// PRIVATE EXPERIMENT. No shipped API and no generic JSON Schema import support.
// Proposals come from emitted schemas; only the public checker can accept them.
import {createHash} from 'node:crypto';
import {s,unwrap} from '../generated-api.mjs';

class Budget extends Error {}
const defaults={seed:1,attempts:100,maxDepth:6,maxNodes:100,maxWidth:6,maxStringLength:24};
const caps={seed:0xffffffff,attempts:10000,maxDepth:64,maxNodes:10000,maxWidth:100,maxStringLength:1000};
const supported=new Set([
  '$schema','$defs','$ref','type','const','enum','anyOf','oneOf','allOf','not',
  'if','then','else','properties','required','additionalProperties','propertyNames',
  'dependentRequired','items','prefixItems','minItems','maxItems','uniqueItems',
  'contains','minContains','maxContains','minimum','maximum','exclusiveMinimum',
  'exclusiveMaximum','multipleOf','minLength','maxLength','minProperties',
  'maxProperties','title','description','examples','default','format',
]);
function options(given){
  for(const key of Object.keys(given))if(!Object.hasOwn(defaults,key))throw new Error(`Unknown budget: ${key}`);
  const value={...defaults,...given};
  for(const [key,n] of Object.entries(value)){
    if(!Number.isInteger(n)||n<0||n>caps[key]||(key==='maxNodes'&&n===0))throw new Error(`Invalid budget: ${key}`);
  }
  return value;
}
function random(seed){
  let state=seed>>>0;
  return n=>{state=(Math.imul(state,1664525)+1013904223)>>>0;return state%n;};
}
function unsupported(schema,path='',found=[]){
  if(typeof schema==='boolean')return found;
  for(const key of Object.keys(schema))if(!supported.has(key))found.push(`${path}/${key}`);
  for(const key of ['$defs','properties'])for(const [name,child] of Object.entries(schema[key]??{}))unsupported(child,`${path}/${key}/${name}`,found);
  for(const key of ['items','additionalProperties','propertyNames','contains','not','if','then','else']){
    if(schema[key]!==undefined)unsupported(schema[key],`${path}/${key}`,found);
  }
  for(const key of ['allOf','anyOf','oneOf','prefixItems'])for(const [i,child] of (schema[key]??[]).entries())unsupported(child,`${path}/${key}/${i}`,found);
  return found;
}
function resolve(root,reference){
  if(!reference.startsWith('#/'))throw new Error('Experiment only resolves local JSON Pointer references');
  return reference.slice(2).split('/').reduce((node,key)=>{
    const token=key.replaceAll('~1','/').replaceAll('~0','~');
    if(!node||!Object.hasOwn(node,token))throw new Error(`Unresolved reference: ${reference}`);
    return node[token];
  },root);
}
function proposal(schema,root,r,limits,state,depth=0,expansions=0){
  if(depth>limits.maxDepth||++state.nodes>limits.maxNodes||expansions>limits.maxDepth*4+8)throw new Budget();
  if(schema===false)throw new Budget();
  if(schema===true)return null;
  if(Object.hasOwn(schema,'const'))return schema.const;
  if(schema.enum)return schema.enum[r(schema.enum.length)];
  if(schema.$ref)return proposal(resolve(root,schema.$ref),root,r,limits,state,depth,expansions+1);
  const alternatives=schema.anyOf??schema.oneOf;
  if(alternatives)return proposal(alternatives[r(alternatives.length)],root,r,limits,state,depth,expansions+1);
  if(schema.allOf){
    // Generate from one branch and check the entire conjunction afterwards.
    // Never merge object keys as though replacement meant conjunction.
    const bases=schema.allOf.filter(child=>child.type||child.$ref||child.anyOf||child.oneOf||child.allOf||Object.hasOwn(child,'const')||child.enum);
    if(!bases.length)return null;
    return proposal(bases[r(bases.length)],root,r,limits,state,depth,expansions+1);
  }
  const child=part=>proposal(part,root,r,limits,state,depth+1,0);
  const length=(minimum=0,maximum=limits.maxWidth)=>{
    const upper=Math.min(maximum,limits.maxWidth);
    if(minimum>upper)throw new Budget();
    return minimum+r(upper-minimum+1);
  };
  switch(schema.type){
    case 'null':return null;
    case 'boolean':return r(2)===1;
    case 'integer':case 'number':{
      const integer=schema.type==='integer';
      let low=schema.minimum??schema.exclusiveMinimum??-10;
      let high=schema.maximum??schema.exclusiveMaximum??Math.max(10,low+10);
      if(schema.minimum===undefined&&schema.exclusiveMinimum===undefined)low=Math.min(-10,high-10);
      if(integer){low=Math.ceil(low);high=Math.floor(high);}
      const choices=[low,high,0,low+(high-low)*r(1001)/1000];
      const value=choices[r(choices.length)];
      return integer?Math.round(value):value;
    }
    case 'string':{
      const minimum=schema.minLength??0,maximum=Math.min(schema.maxLength??limits.maxStringLength,limits.maxStringLength);
      if(minimum>maximum)throw new Budget();
      const n=minimum+r(maximum-minimum+1);
      const alphabet=['a','b','x',' ','😀'];
      return Array.from({length:n},()=>alphabet[r(alphabet.length)]).join('');
    }
    case 'array':{
      if(schema.prefixItems){
        if(schema.prefixItems.length>limits.maxWidth)throw new Budget();
        return schema.prefixItems.map(child);
      }
      const count=length(schema.minItems,schema.maxItems);
      return Array.from({length:count},()=>child(schema.items??true));
    }
    case 'object':{
      const value=Object.create(null),required=schema.required??[],properties=schema.properties??{};
      if(required.length>limits.maxWidth)throw new Budget();
      for(const key of required)value[key]=child(properties[key]??schema.additionalProperties??true);
      for(const key of Object.keys(properties).sort())if(!Object.hasOwn(value,key)&&Object.keys(value).length<limits.maxWidth&&r(2))value[key]=child(properties[key]);
      if(!Object.keys(properties).length&&schema.additionalProperties&&schema.additionalProperties!==false){
        const count=length(schema.minProperties,schema.maxProperties);
        for(let i=0;i<count;i++)value[`key${i}`]=child(schema.additionalProperties);
      }
      return value;
    }
    default:return [null,false,0,'',[],{}][r(6)];
  }
}
function within(value,limits,depth=0,state={nodes:0}){
  if(depth>limits.maxDepth||++state.nodes>limits.maxNodes)return false;
  if(typeof value==='string')return Array.from(value).length<=limits.maxStringLength;
  if(typeof value==='number')return Number.isFinite(value);
  if(!value||typeof value!=='object')return true;
  if(!Array.isArray(value)&&Object.keys(value).some(key=>Array.from(key).length>limits.maxStringLength))return false;
  const children=Array.isArray(value)?value:Object.values(value);
  return children.length<=limits.maxWidth&&children.every(child=>within(child,limits,depth+1,state));
}
function search(definition,accept,given){
  const limits=options(given),text=s.schema_string(definition,s.JsonLayout$Compact$const),schema=JSON.parse(text);
  const replay={options:limits,schemaSha256:createHash('sha256').update(text).digest('hex')};
  const unknown=unsupported(schema);
  if(unknown.length)return {status:'unsupported',keywords:unknown,replay};
  const r=random(limits.seed);let budgetFailures=0;
  for(let attempt=1;attempt<=limits.attempts;attempt++){
    let raw;
    try{raw=proposal(schema,schema,r,limits,{nodes:0});}
    catch(error){if(!(error instanceof Budget))throw error;budgetFailures++;continue;}
    if(!within(raw,limits)){budgetFailures++;continue;}
    const admitted=s.parse(JSON.stringify(raw));
    if(admitted.isOk()&&accept(admitted[0]).isOk())return {status:'generated',json:admitted[0],attemptsUsed:attempt,replay};
  }
  return {status:'exhausted',attemptsUsed:limits.attempts,budgetFailures,replay};
}
export function generate(definition,given={}){
  const result=search(definition,json=>s.validate(definition,json),given);
  return {...result,acceptance:'structural'};
}
export function generateContract(contract,given={}){
  const result=search(s.contract_definition(contract),json=>s.validate_contract(contract,json),given);
  return {...result,acceptance:'semantic-contract',requirements:[...s.contract_requirements(contract)]};
}

function* proposals(value,depth=0){
  yield null;
  if(typeof value==='boolean'){yield false;return;}
  if(typeof value==='number'){yield 0;yield Math.trunc(value/2);return;}
  if(typeof value==='string'){yield '';yield Array.from(value).slice(0,1).join('');return;}
  if(!value||depth>=64)return;
  if(Array.isArray(value)){
    yield [];
    for(let i=0;i<value.length;i++){
      yield value.filter((_,index)=>index!==i);
      for(const smaller of proposals(value[i],depth+1))yield value.map((v,index)=>index===i?smaller:v);
    }
  }else{
    yield {};
    for(const key of Object.keys(value).sort()){
      const smaller=Object.assign(Object.create(null),value);delete smaller[key];yield smaller;
      for(const item of proposals(value[key],depth+1))yield Object.assign(Object.create(null),value,{[key]:item});
    }
  }
}
function cost(value){
  if(value===null)return 0;
  if(typeof value==='number')return 1+Math.min(Math.abs(value),Number.MAX_SAFE_INTEGER);
  if(typeof value==='boolean')return value?2:1;
  if(typeof value==='string')return 1+Array.from(value).length;
  const children=Array.isArray(value)?value:Object.values(value);
  return 1+children.length+children.reduce((n,child)=>n+cost(child),0);
}
function minimize(accept,json,fails,budgets={}){
  for(const key of Object.keys(budgets))if(!['maxSteps','maxCandidates'].includes(key))throw new Error(`Unknown shrink budget: ${key}`);
  const {maxSteps=100,maxCandidates=1000}=budgets;
  for(const n of [maxSteps,maxCandidates])if(!Number.isInteger(n)||n<0||n>10000)throw new Error('Invalid shrink budget');
  if(!accept(json).isOk()||!fails(json))throw new Error('Initial value must be accepted and retain the failing property');
  let raw=JSON.parse(s.to_string(json,s.JsonLayout$Compact$const)),current=json,tried=0;
  if(!within(raw,{maxDepth:64,maxNodes:10000,maxWidth:100,maxStringLength:1000}))throw new Error('Shrink input exceeds prototype size limits');
  for(let step=0;step<maxSteps;step++){
    let changed=false;
    for(const candidate of proposals(raw)){
      if(tried>=maxCandidates)return {status:'budget-exhausted',json:current,tried,steps:step};
      tried++;
      if(cost(candidate)>=cost(raw))continue;
      const next=unwrap(s.parse(JSON.stringify(candidate)));
      if(accept(next).isOk()&&fails(next)){raw=candidate;current=next;changed=true;break;}
    }
    if(!changed)return {status:'minimal-within-proposals',json:current,tried,steps:step};
  }
  return {status:'budget-exhausted',json:current,tried,steps:maxSteps};
}
export const shrink=(definition,json,fails,budgets)=>minimize(value=>s.validate(definition,value),json,fails,budgets);
export const shrinkContract=(contract,json,fails,budgets)=>minimize(value=>s.validate_contract(contract,value),json,fails,budgets);
