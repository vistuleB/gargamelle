// Deterministic recipes and proposals shared by JavaScript and native evidence.
import {allKinds,specimen,proposal} from './recipe-model.mjs';
export const seeds=[0x10203040,0x91abcdef,0x12345678,0xdeadbeef,0x71423,0x55555555,0xabcdef01,0x37891,0x76543210,0xfedcba98];
export const common=[null,true,false,0,1,-1,1.5,'','x','a','ab','😀','e\u0301','\0','\u{10ffff}',[],{},[null],{value:null},Number.MAX_SAFE_INTEGER+1];
export function random(seed){let x=seed>>>0;return n=>{x^=x<<13;x^=x>>>17;x^=x<<5;return (x>>>0)%n;};}
export function generated(r,depth){
 if(depth===0){const a=specimen(allKinds[r(8)]);if(a.kind==='constant')a.value=[null,true,false,'c',-1,0,1][r(7)];if(a.kind==='string'&&r(2)){a.min=r(2);a.max=3;if(r(2))a.patterns=['a','b','a'];}if(a.kind==='integer'&&r(2)){a.min=-3;a.max=3;}if(a.kind==='number'&&r(2)){a.min=-1.5;a.max=2.5;a.exclusiveMin=!!r(2);a.exclusiveMax=!!r(2);}return a;}
 const kind=allKinds[8+r(allKinds.length-8)];
 const a=specimen(kind,generated(r,depth-1));
 const names=['__proto__','constructor','toString','','a/b','~1','10','2','01','😀'];
 if(kind==='conditional'&&r(2))a.alternative={kind:'boolean'};
 if(kind==='record'){a.open=!!r(2);const offset=r(names.length);a.fields.forEach((f,i)=>f.name=names[(offset+i)%names.length]);}
 if(kind==='tagged'){a.tag=names[r(names.length)];a.branches.forEach((b,i)=>b.tag=names[(i+r(3)*2)%names.length]);if(a.branches[0].tag===a.branches[1].tag)a.branches[1].tag+='-other';}

 if(kind==='any'||kind==='one'){if(r(2))a.children.push(specimen('boolean'));if(r(4)===0)a.children.push(a.children[0]);}
 return a;
}
export function mutations(v){
 if(Array.isArray(v))return [[],[...v,...v,...v,...v],v.map((x,i)=>i===0?false:x)];
 if(v&&typeof v==='object'){const entries=Object.entries(v);return [{},{...v,unexpected:true},Object.fromEntries(entries.slice(1)),Object.fromEntries(entries.map(([k,x],i)=>[k,i===0?false:x]))];}
 if(typeof v==='string')return ['',v+'!',v+v+v+v,v.length? v.slice(1):'x'];
 if(typeof v==='number')return [v-1,v+1,v+0.5];
 return [null,false,'x'];
}

export function corpus() {
 const rows=[];
 const add=(recipe,values,context)=>rows.push({recipe,inputs:values.map(value=>JSON.stringify(value)),context});
 for(const seed of seeds){const r=random(seed);for(let i=0;i<50;i++){
  const depth=i%7,recipe=generated(r,depth),valid=proposal(recipe,r);
  const values=[valid,...mutations(valid),...Array.from({length:8},()=>proposal(recipe,r))];
  while(values.length<20)values.push(common[r(common.length)]);
  add(recipe,values.slice(0,20),{seed,index:i,depth});
 }}
 const parents=['array','dictionary','record','nullable','any','one','tagged','description','title','map','tuple','property_names','contains','conditional','exclude'];
 for(const parent of parents)for(const child of allKinds){const recipe=specimen(parent,specimen(child));add(recipe,[proposal(recipe),...common],{seed:'edges',index:parent+'-'+child});}
 for(const kind of allKinds){const child=specimen(kind),recipe={kind:'array',child};add(recipe,[proposal(child),...common].map(value=>[value]),{seed:'nested',index:kind});}
 const corrupt=value=>Array.isArray(value)?value.map(corrupt):value&&typeof value==='object'?Object.fromEntries(Object.entries(value).map(([key,child])=>[key,corrupt(child)])):false;
 for(const kind of parents.filter(kind=>kind!=='tagged')){
  let recipe={kind:'string'};
  for(let depth=0;depth<50;depth++)recipe=kind==='record'?{kind,fields:[{name:'nested',child:recipe}]}:kind==='array'||kind==='dictionary'?{kind,child:recipe,min:1,max:2}:specimen(kind,recipe);
  const valid=kind==='nullable'?'x':proposal(recipe);
  add(recipe,[valid,corrupt(valid),null],{seed:'depth50',index:kind});
 }
 for(const recipe of [{kind:'integer',min:-2,max:2},{kind:'string',min:1,max:2},{kind:'array',child:{kind:'string'},min:1,max:2},{kind:'dictionary',child:{kind:'string'},min:1,max:2}]){
  const values=recipe.kind==='integer'?[-3,-2,-1,1,2,3]:recipe.kind==='string'?['','x','xx','xxx']:recipe.kind==='array'?[[],['x'],['x','x'],['x','x','x']]:[{}, {a:'x'},{a:'x',b:'x'},{a:'x',b:'x',c:'x'}];
  add(recipe,values,{seed:'bounds',index:recipe.kind});
 }
 return rows;
}
