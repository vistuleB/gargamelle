// Test-only adapter from generated definition recipes to PUBLIC Gleam constructors.
// Recipes are not a library schema-import API and never inject a Node/Definition.
import * as s from '../build/dev/javascript/gargamelle/gargamelle.mjs';
import { Ok, toList } from '../build/dev/javascript/gargamelle/gleam.mjs';
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
    case 'exclude': d=s.exclude(build(a.child),build(a.forbidden));break;
    case 'conditional': d=a.alternative?s.if_then_else(build(a.child),build(a.condition),build(a.consequence),build(a.alternative)):s.if_then(build(a.child),build(a.condition),build(a.consequence));break;
    case 'contains': d=s.map(unwrap(s.contains(s.array(build(a.child)),build(a.matching),a.minimum,option(a.maximum))),xs=>[...xs]);break;
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
export {allKinds,childNodes,proposal,specimen} from './recipe-model.mjs';
