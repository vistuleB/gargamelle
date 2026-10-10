import { childNodes } from './generated-api.mjs';
export function shrinkValues(v){return [null,false,0,'',[],{},...(Array.isArray(v)?[v.slice(0,1),...v]:v&&typeof v==='object'?[Object.fromEntries(Object.entries(v).slice(0,1)),...Object.values(v)]:typeof v==='string'?[v.slice(0,1)]:[])];}
// Operational exceptions are deliberately propagated. They are never a rejection
// and cannot be used to claim that a smaller counterexample no longer fails.
export function minimize(recipe,value,hasMismatch){
 let a=recipe,v=value,changed=true;
 while(changed){
  changed=false;
  for(const candidate of childNodes(a)){if(hasMismatch(candidate,v)){a=candidate;changed=true;break;}}
  if(changed)continue;
  for(const candidate of shrinkValues(v)){if(JSON.stringify(candidate).length<JSON.stringify(v).length&&hasMismatch(a,candidate)){v=candidate;changed=true;break;}}
 }
 return {recipe:a,value:v};
}

export async function minimizeAsync(recipe,value,hasMismatch){
 let a=recipe,v=value,changed=true;
 while(changed){
  changed=false;
  for(const candidate of childNodes(a)){if(await hasMismatch(candidate,v)){a=candidate;changed=true;break;}}
  if(changed)continue;
  for(const candidate of shrinkValues(v)){if(JSON.stringify(candidate).length<JSON.stringify(v).length&&await hasMismatch(a,candidate)){v=candidate;changed=true;break;}}
 }
 return {recipe:a,value:v};
}
