import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import assert from 'node:assert/strict';
const selection=JSON.parse(readFileSync(new URL('./test262-selection.json',import.meta.url)));
export function collectTest262(root) {
for(const [path,hash] of Object.entries(selection.files)) {
 assert.equal(createHash('sha256').update(readFileSync(join(root,path))).digest('hex'),hash,`Test262 source changed: ${path}`);
}
const cases=[], exclusions=[],passed=[], hashes={};
const omitted={flags:0,nonScalarPattern:0,largeText:0};
const paths=Object.keys(selection.files).filter(path=>path.startsWith('test/')).map(path=>join(root,path));
for(const path of paths){
 const source=readFileSync(path,'utf8'),rel=path.slice(root.length+1);
 hashes[rel]=createHash('sha256').update(source).digest('hex');
 if(/negative:|flags:.*(?:async|module)/.test(source)){exclusions.push({file:rel,reason:'parse-negative/async/module'});continue;}
 const found=[];
 const capture=(pattern,flags,text)=>{
  if(flags!==''&&flags!=='u'){omitted.flags++;return;}
  if(!pattern.isWellFormed()){omitted.nonScalarPattern++;return;}
  if(text.length>4096){omitted.largeText++;return;}
  // The public engine always uses u; non-u sources are derived u projections.
  found.push({pattern,text,source:rel,originalFlags:flags});
 };
 const context=vm.createContext({capture});
 try{
  const includes=source.match(/includes:\s*\[([^\]]*)\]/)?.[1].split(',').map(x=>x.trim())??[];
  for(const h of ['sta.js','assert.js',...includes])vm.runInContext(readFileSync(join(root,'harness',h),'utf8'),context,{timeout:1000});
  vm.runInContext(`const NativeRegExp=RegExp, nativeExec=RegExp.prototype.exec;
  RegExp.prototype.exec=function(text){capture(this.source,this.flags,String(text));return nativeExec.call(this,text);};
  RegExp=new Proxy(NativeRegExp,{construct(target,args,newTarget){ const pattern=args[0] instanceof NativeRegExp ? args[0].source : String(args[0]??''),flags=String(args[1]??'');capture(pattern,flags,'');return Reflect.construct(target,args,newTarget);},apply(target,receiver,args){capture(String(args[0]??''),String(args[1]??''),'');return Reflect.apply(target,receiver,args);}});`,context,{timeout:1000});
  vm.runInContext(source,context,{filename:rel,timeout:1000});
  cases.push(...found);passed.push(rel);
 }catch(error){exclusions.push({file:rel,reason:error.name+': '+error.message});}
}
const unique=[...new Map(cases.map(c=>[JSON.stringify([c.pattern,c.text]),c])).values()];
return {cases:unique,passed,exclusions,sourceHashes:hashes,omitted,
  commit:selection.commit,archiveSha256:selection.archiveSha256,
  scope:'Boolean u-mode projections from selected passing Test262 tests; not a full Test262 engine run',
  maxCapturedTextUnits:4096,perFileTimeoutMs:1000};
}
