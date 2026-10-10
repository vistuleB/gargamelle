// Independent test-recipe interpreter: no Gleam constructors or emitted schemas.
// Its output models only the public test adapter's mappings, not runtime internals.
const no = {accepted:false};
const yes = value => ({accepted:true,value});
const object = v => v !== null && typeof v === 'object' && !Array.isArray(v);
const bounded = (a,n) => (a.min == null || n >= a.min) && (a.max == null || n <= a.max);
export function reference(a,v,visit=()=>{},path='$') {
 const child=(c,x,p)=>reference(c,x,visit,p);
 let r=no;
 switch(a.kind) {
 case 'boolean': if(typeof v==='boolean')r=yes(v);break;
 case 'null': if(v===null)r=yes(null);break;
 case 'string': if(typeof v==='string'&&bounded(a,[...v].length)&&(a.patterns??[]).every(p=>new RegExp(p,'u').test(v)))r=yes(v);break;
 case 'integer': if(Number.isSafeInteger(v)&&bounded(a,v))r=yes(v);break;
 case 'number': if(typeof v==='number'&&Number.isFinite(v)&&(a.min==null||(a.exclusiveMin?v>a.min:v>=a.min))&&(a.max==null||(a.exclusiveMax?v<a.max:v<=a.max)))r=yes(v);break;
 case 'enum': if(a.values.includes(v))r=yes(v);break;
 case 'constant': if(v===a.value)r=yes(v);break;
 case 'recursive': {
  if(typeof v==='number'&&Number.isFinite(v))r=yes({leaf:v});
  else if(Array.isArray(v)){const results=v.map((x,i)=>child(a,x,path+'/child/'+i));if(results.every(x=>x.accepted))r=yes({children:results.map(x=>x.value)});}
  break;
 }
 case 'contains': {
  if(!Array.isArray(v))break;
  const items=v.map(x=>child(a.child,x,path+'/child'));
  const count=v.filter(x=>child(a.matching,x,path+'/matching').accepted).length;
  if(items.every(x=>x.accepted)&&count>=a.minimum&&(a.maximum==null||count<=a.maximum))r=yes(items.map(x=>x.value));break;
 }
 case 'property_names': {
  if(!object(v))break;
  const values=Object.entries(v).map(([k,x])=>[k,child(a.child,x,path+'/child'),child(a.keys,k,path+'/key')]);
  if(values.every(([,x,k])=>x.accepted&&k.accepted))r=yes(Object.fromEntries(values.map(([k,x])=>[k,x.value])));break;
 }
 case 'tuple': {
  if(!Array.isArray(v)||v.length!==a.children.length)break;
  const results=a.children.map((c,i)=>child(c,v[i],path+'/position/'+i));
  if(results.every(x=>x.accepted))r=yes(results.map(x=>x.value));break;
 }
 case 'array': case 'dictionary': {
  if(a.kind==='array'?!Array.isArray(v):!object(v))break;
  const entries=Object.entries(v), values=entries.map(([k,x])=>[k,child(a.child,x,path+'/child')]);
  if(bounded(a,entries.length)&&values.every(([,x])=>x.accepted))r=yes(a.kind==='array'?values.map(([,x])=>x.value):Object.fromEntries(values.map(([k,x])=>[k,x.value])));
  break;
 }
 case 'record': {
  if(!object(v))break;
  let valid=a.open||Object.keys(v).every(k=>a.fields.some(f=>f.name===k));const out=[];
  for(const [i,f] of a.fields.entries()){
   if(!Object.hasOwn(v,f.name)){
    if(f.presence==='optional'){out.push([f.name,{none:true}]);continue;}
    if(f.presence!=='defaulted'){valid=false;continue;}
   }
   const x=child(f.child,Object.hasOwn(v,f.name)?v[f.name]:f.default,path+'/field/'+i);
   if(!x.accepted)valid=false;else out.push([f.name,f.presence==='optional'?{some:x.value}:x.value]);
  }
  if(valid)r=yes(Object.fromEntries(out));break;
 }
 case 'nullable': r=v===null?yes({none:true}):child(a.child,v,path+'/child');if(v!==null&&r.accepted)r=yes({some:r.value});break;
 case 'any': case 'one': {
  const results=a.children.map((c,i)=>child(c,v,path+'/branch/'+i)).filter(x=>x.accepted);
  if(a.kind==='any'?results.length>0:results.length===1)r=results[0];break;
 }
 case 'tagged': {
  if(!object(v)||!Object.hasOwn(v,a.tag))break;
  const i=a.branches.findIndex(b=>b.tag===v[a.tag]);if(i<0)break;
  const b=a.branches[i], payload=Object.fromEntries(Object.entries(v).filter(([k])=>k!==a.tag));
  const x=child({kind:'record',fields:b.fields,open:b.open},payload,path+'/variant/'+i);
  if(x.accepted)r=yes({tag:b.tag,payload:x.value});break;
 }
 case 'description':case 'title':case 'map':r=child(a.child,v,path+'/child');if(a.kind==='map'&&r.accepted)r=yes({mapped:r.value});break;
 default:throw new Error('Unknown reference recipe '+a.kind);
 }
 visit(path,a.kind,r.accepted);
 return r;
}
