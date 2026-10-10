// Test-only adapter from generated definition recipes to PUBLIC Gleam constructors.
// Recipes are not a library schema-import API and never inject a Node/Definition.
import * as s from '../build/dev/javascript/concord/concord.mjs';
import { Ok, toList } from '../build/dev/javascript/concord/gleam.mjs';
import { Some, Option$None$const as None } from '../build/dev/javascript/gleam_stdlib/gleam/option.mjs';
export { s, Ok, toList, Some, None };
export const unwrap = r => { if (!(r instanceof Ok)) throw new Error(`Construction/admission failed: ${JSON.stringify(r)}`); return r[0]; };
const option = x => x == null ? None : new Some(x);
const presence = o => o instanceof Some ? { some:o[0] } : { none:true };
function objectRecord(fields) {
  const combine = (i, values) => i===fields.length ? Object.fromEntries(fields.map((f,j)=>[f.name, f.presence==='optional'?presence(values[j]):values[j]])) : value=>combine(i+1,[...values,value]);
  let r=s.record(combine(0,[]));
  for(const f of fields) {
    const d=build(f.child);
    r=unwrap(f.presence==='optional'?s.optional(r,f.name,d):f.presence==='defaulted'?s.defaulted(r,f.name,d,unwrap(s.parse(JSON.stringify(f.default)))):s.required(r,f.name,d));
  }
  return r;
}
export function build(a) {
  let d;
  switch(a.kind) {
    case 'boolean': d=s.boolean(); break;
    case 'null': d=s.map(s.null$(),()=>null); break;
    case 'string': d=s.text(); if(a.min!=null||a.max!=null)d=unwrap(s.bounds(d,option(a.min),option(a.max))); for(const p of a.patterns??[])d=unwrap(s.pattern(d,p)); break;
    case 'integer': d=s.safe_integer(); if(a.min!=null||a.max!=null)d=unwrap(s.bounds(d,option(a.min),option(a.max))); break;
    case 'number': d=s.number(); if(a.min!=null||a.max!=null)d=unwrap(s.number_bounds(d,a.min==null?None:new Some(a.exclusiveMin?new s.Exclusive(a.min):new s.Inclusive(a.min)),a.max==null?None:new Some(a.exclusiveMax?new s.Exclusive(a.max):new s.Inclusive(a.max)))); break;
    case 'enum': d=unwrap(s.string_enum(toList(a.values))); break;
    case 'constant': d=a.value===null?s.map(s.null_constant(),()=>null):typeof a.value==='string'?s.string_constant(a.value):typeof a.value==='boolean'?s.boolean_constant(a.value):unwrap(s.integer_constant(a.value)); break;
    case 'recursive': d=unwrap(s.recursive('generated-tree',self=>s.any_of(toList([s.map(s.number(),x=>({leaf:x})),s.map(s.array(self),xs=>({children:[...xs]}))])))); break;
    case 'array': d=s.array(build(a.child)); if(a.min!=null||a.max!=null)d=unwrap(s.bounds(d,option(a.min),option(a.max))); d=s.map(d,x=>[...x]); break;
    case 'tuple': {
      const combine=(i,values)=>i===a.children.length?values:x=>combine(i+1,[...values,x]);
      let t=s.tuple(combine(0,[]));
      for(const child of a.children)t=s.element(t,build(child));
      d=s.finish_tuple(t);break;
    }
    case 'property_names': d=s.map(unwrap(s.property_names(s.dictionary(build(a.child)),build(a.keys))),xs=>Object.fromEntries(xs));break;
    case 'dictionary': d=s.dictionary(build(a.child)); if(a.min!=null||a.max!=null)d=unwrap(s.bounds(d,option(a.min),option(a.max))); d=s.map(d,x=>Object.fromEntries(x)); break;
    case 'record': d=s.finish(objectRecord(a.fields),a.open?s.Policy$Open$const:s.Policy$Closed$const); break;
    case 'nullable': d=s.map(s.nullable(build(a.child)),presence); break;
    case 'any': d=unwrap(s.any_of(toList(a.children.map(build)))); break;
    case 'one': d=unwrap(s.one_of(toList(a.children.map(build)))); break;
    case 'tagged': d=unwrap(s.tagged(a.tag,toList(a.branches.map(b=>{
      let v=s.variant(b.tag,objectRecord(b.fields),b.open?s.Policy$Open$const:s.Policy$Closed$const);
      if(b.description!=null)v=s.variant_description(v,b.description);
      return s.variant_map(v,payload=>({tag:b.tag,payload}));
    })))); break;
    case 'description': d=s.description(build(a.child),a.value??'description'); break;
    case 'title': d=s.title(build(a.child),a.value??'title'); break;
    case 'map': d=s.map(build(a.child),x=>({mapped:x})); break;
    default: throw new Error(`Unknown recipe ${a.kind}`);
  }
  return d;
}
export function evaluate(definition, value) {
  return evaluateText(definition,JSON.stringify(value));
}
export function evaluateText(definition, text) {
  const input=unwrap(s.parse(text));
  const before=s.value_text(input);
  const result=s.decode(definition,input);
  if(s.value_text(input)!==before)throw new Error('Decoder mutated input');
  return {accepted:result instanceof Ok, value:result[0]};
}
export const emitted=d=>JSON.parse(s.emit_text(d));
export const allKinds=['boolean','null','string','integer','enum','constant','number','recursive','array','dictionary','record','nullable','any','one','tagged','description','title','map','tuple','property_names'];
export function childNodes(a) {
  return a.keys?[a.child,a.keys]:a.child?[a.child]:a.children??(a.fields?a.fields.map(f=>f.child):a.branches?a.branches.flatMap(b=>b.fields.map(f=>f.child)):[]);
}
// Construction witness is generated from the recipe, never from the library's decoder.
// Overlapping unions may have no witness; the independent oracle classifies all proposals.
export function proposal(a,r=()=>0) {
 const p=c=>proposal(c,r);
 switch(a.kind){
 case 'boolean':return !!r(2);case 'null':return null;case 'string':return (a.patterns??[]).length?'ab':'x'.repeat(a.min??1);case 'integer':return a.min??0;
 case 'recursive':return r(2)?[0.5,[]]:0.5;
 case 'number':return a.min==null?(a.max==null?0.5:a.max-(a.exclusiveMax?0.5:0)) : a.min+(a.exclusiveMin?0.5:0);
 case 'enum':return a.values[r(a.values.length)];case 'constant':return a.value;
 case 'property_names':return {k0:p(a.child)};
 case 'tuple':return a.children.map(p);
 case 'array':return Array.from({length:a.min??1},()=>p(a.child));
 case 'dictionary':return Object.fromEntries(Array.from({length:a.min??1},(_,i)=>['k'+i,p(a.child)]));
 case 'record':return Object.fromEntries(a.fields.filter(f=>!['defaulted','optional'].includes(f.presence)||r(2)).map(f=>[f.name,p(f.child)]));
 case 'nullable':return r(2)?p(a.child):null;case 'any':case 'one':return p(a.children[r(a.children.length)]);
 case 'tagged':{const b=a.branches[r(a.branches.length)];return {[a.tag]:b.tag,...Object.fromEntries(b.fields.map(f=>[f.name,p(f.child)]))};}
 case 'description':case 'title':case 'map':return p(a.child);
 }
}
export function specimen(kind,child={kind:'string'}) {
 switch(kind){
 case 'property_names':return {kind,child,keys:{kind:'string',min:1,max:8,patterns:['^k']}};
 case 'tuple':return {kind,children:[child,{kind:'string'}]};
 case 'enum':return {kind,values:['a','b']};case 'constant':return {kind,value:'constant'};
 case 'array':case 'dictionary':return {kind,child,min:0,max:3};
 case 'nullable':case 'description':case 'title':case 'map':return {kind,child};
 case 'any':case 'one':return {kind,children:[child]};
 case 'record':return {kind,fields:[{name:'value',child},{name:'optional',child,presence:'optional'},{name:'default',child:{kind:'string'},presence:'defaulted',default:'d'}]};
 case 'tagged':return {kind,tag:'kind',branches:[{tag:'a',fields:[{name:'value',child}],description:'variant a'},{tag:'b',fields:[]}]};
 default:return {kind};
 }
}
