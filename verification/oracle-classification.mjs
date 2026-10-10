import assert from 'node:assert/strict';
import {compileOracle} from './oracle.mjs';
// Diagnose the pinned Ajv __proto__ defect by a semantics-preserving key rename.
// Merely containing that key is NOT enough to excuse a disagreement.
export function classifySplit(schema,value,ajv,hyperjump) {
 if(ajv.accepted===hyperjump.accepted)return null;
 const replacement='__concord_proto_probe__';
 assert.ok(!JSON.stringify([schema,value]).includes(replacement),'rename probe collision');
 let found=false;
 function rewrite(s){
  const out={...s};
  if(s.properties){out.properties=Object.fromEntries(Object.entries(s.properties).map(([k,c])=>{if(k==='__proto__')found=true;return [k==='__proto__'?replacement:k,rewrite(c)];}));}
  if(s.required)out.required=s.required.map(k=>k==='__proto__'?replacement:k);
  for(const k of ['anyOf','oneOf','allOf','prefixItems'])if(s[k])out[k]=s[k].map(rewrite);
  for(const k of ['items','additionalProperties','propertyNames','contains','if','then','else'])if(s[k]&&typeof s[k]==='object')out[k]=rewrite(s[k]);
  return out;
 }
 function input(v){return Array.isArray(v)?v.map(input):v&&typeof v==='object'?Object.fromEntries(Object.entries(v).map(([k,x])=>[k==='__proto__'?replacement:k,input(x)])):v;}
 const renamed=rewrite(schema);
 assert.ok(found,'Unclassified oracle disagreement: no declared __proto__ property');
 assert.equal(compileOracle(renamed)(input(value)).accepted,hyperjump.accepted,'Unclassified disagreement survives key rename');
 return 'ajv-declared-proto-key';
}
