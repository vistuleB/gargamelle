// Test recipes and proposals; independent of compiled library modules.
export const allKinds=['boolean','null','string','integer','enum','constant','number','recursive','array','dictionary','record','nullable','any','one','tagged','description','title','map','tuple','property_names','contains','conditional','exclude'];
export function childNodes(a) {
  return a.forbidden?[a.child,a.forbidden]:a.condition?[a.child,a.condition,a.consequence,...(a.alternative?[a.alternative]:[])]:a.matching?[a.child,a.matching]:a.keys?[a.child,a.keys]:a.child?[a.child]:a.children??(a.fields?a.fields.map(f=>f.child):a.branches?a.branches.flatMap(b=>b.fields.map(f=>f.child)):[]);
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
 case 'exclude':return p(a.child);
 case 'conditional':return p(a.child);
 case 'contains':return Array.from({length:Math.max(1,a.minimum)},()=>p(a.child));
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
 case 'exclude':return {kind,child,forbidden:{kind:'constant',value:true}};
 case 'conditional':return {kind,child,condition:{kind:'constant',value:true},consequence:{kind:'constant',value:false}};
 case 'contains':return {kind,child,matching:{kind:'number'},minimum:0,maximum:1};
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
