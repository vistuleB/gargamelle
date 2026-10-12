// Research instrumentation only. Preserve command behavior, output and status.
import cp from 'node:child_process';
import {appendFileSync} from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import {performance} from 'node:perf_hooks';
const file=process.env.GARGAMELLE_TRACE_FILE;
if(file){
 let sequence=0;
 const write=row=>appendFileSync(file,JSON.stringify(row)+'\n');
 function begin(kind,command,args,options){
  const id=`${process.pid}:${++sequence}`;
  const row={event:'start',id,parent:process.env.GARGAMELLE_TRACE_PARENT??null,pid:process.pid,kind,command:String(command),args:Array.isArray(args)?args.map(x=>String(x).slice(0,600)):[],cwd:String(options?.cwd??process.cwd()),at:Date.now()};
  write(row);const started=performance.now();
  return {id,row,started,options:{...options,env:{...(options?.env??process.env),GARGAMELLE_TRACE_PARENT:id}}};
 }
 const originals={spawnSync:cp.spawnSync,spawn:cp.spawn,execFileSync:cp.execFileSync};
 for(const kind of ['spawnSync','execFileSync']){
  cp[kind]=function(command,args,options){
   if(!Array.isArray(args)){options=args;args=[];}
   const timing=begin(kind,command,args,options);
   try{
    const result=originals[kind].call(cp,command,args,timing.options);
    write({event:'end',id:timing.id,pid:process.pid,at:Date.now(),durationMs:performance.now()-timing.started,status:kind==='spawnSync'?result.status:0,signal:kind==='spawnSync'?result.signal:null});
    return result;
   }catch(error){write({event:'end',id:timing.id,pid:process.pid,at:Date.now(),durationMs:performance.now()-timing.started,status:error.status??null,error:error.name});throw error;}
  };
 }
 cp.spawn=function(command,args,options){
  if(!Array.isArray(args)){options=args;args=[];}
  const timing=begin('spawn',command,args,options);
  const child=originals.spawn.call(cp,command,args,timing.options);
  child.once('close',(status,signal)=>write({event:'end',id:timing.id,pid:process.pid,childPid:child.pid,at:Date.now(),durationMs:performance.now()-timing.started,status,signal}));
  return child;
 };
 syncBuiltinESMExports();
}
