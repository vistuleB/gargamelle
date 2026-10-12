import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
const config=JSON.parse(readFileSync(process.argv[2]));
const read=path=>JSON.parse(readFileSync(path));
const seconds=(a,b)=>(Date.parse(b)-Date.parse(a))/1000;
function phase(row){
 const args=row.args.join(' ');
 if(row.command==='npm')return ({'run verify':'JavaScript verification','run check:release':'Evidence review','run verify:erlang-primitives':'Native verification'})[args]??args;
 if(row.command==='gleam'&&args==='docs build')return 'Documentation';
 if(row.command==='gleam'&&args==='export hex-tarball')return 'Archive export';
 if(row.command==='tar')return 'Archive extraction/listing';
 if(row.command==='gleam'&&row.args[0]==='run')return row.args.includes('javascript')?'Archive consumers: JavaScript':'Archive consumers: Erlang';
 if(row.command==='make')return 'Archive helper compilation';
 if((row.command==='gleam'&&args==='--version')||row.command==='erl')return 'Version recording';
 return `${row.command} ${args}`;
}
const platforms=config.platforms.map(({name,directory})=>{
 const events=readFileSync(join(directory,'release-timings.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
 const starts=new Map(events.filter(x=>x.event==='start').map(x=>[x.id,x]));
 const commands=events.filter(x=>x.event==='end').map(end=>{const start=starts.get(end.id);assert.ok(start);return {...start,...end,startedAt:start.at,endedAt:end.at,seconds:end.durationMs/1000};});
 const root=commands.find(x=>x.kind==='stage'&&x.args.join(' ')==='run prepare:release');assert.ok(root);assert.equal(root.status,0);
 const pid=commands.find(x=>x.command==='npm'&&x.args.join(' ')==='run verify').pid;
 const direct=commands.filter(x=>x.pid===pid);
 const phases={};for(const row of direct){const label=phase(row);phases[label]=(phases[label]??0)+row.seconds;}
 phases['Runner/inspection overhead']=root.seconds-direct.reduce((n,x)=>n+x.seconds,0);
 const negative=commands.filter(x=>x.command==='gleam'&&x.cwd?.includes('schema-contract-negative-'));
 const tap=readFileSync(join(directory,'node.tap'),'utf8');
 const tests=[...tap.matchAll(/# Subtest: ([^\n]+)\n[\s\S]*?duration_ms: ([\d.]+)/g)].map(m=>({name:m[1],seconds:Number(m[2])/1000})).sort((a,b)=>b.seconds-a.seconds);
 const native=readFileSync(join(directory,'release-native.log'),'utf8');
 const nativeTests=[...native.matchAll(/✔ (.*?) \(([\d.]+)ms\)/g)].map(m=>({name:m[1],seconds:Number(m[2])/1000})).sort((a,b)=>b.seconds-a.seconds);
 const preparation=read(join(directory,'release-preparation.json'));assert.equal(preparation.status,'prepared');
 return {name,totalSeconds:root.seconds,phases,directCommands:direct,allCommands:commands,negativeCompilation:{calls:negative.length,seconds:negative.reduce((n,x)=>n+x.seconds,0),targets:Object.fromEntries(['javascript','erlang'].map(target=>[target,negative.filter(x=>x.args.includes(target)).reduce((n,x)=>n+x.seconds,0)]))},slowestNodeTests:tests.slice(0,10),slowestNativeTests:nativeTests.slice(0,10),runtime:preparation.versions};
});
const ci=read(config.ciRun);
const workflow={createdAt:ci.createdAt,finishedAt:ci.updatedAt,totalSeconds:seconds(ci.createdAt,ci.updatedAt),jobs:ci.jobs.map(j=>({name:j.name,queueSeconds:seconds(ci.createdAt,j.startedAt),totalSeconds:seconds(j.startedAt,j.completedAt),steps:j.steps.map(s=>({name:s.name,seconds:seconds(s.startedAt,s.completedAt)}))}))};
const result={measurementCommit:config.measurementCommit,releaseCommit:config.releaseCommit,platforms,workflow,notes:['Independent instrumented runs; every original release check retained','Only subprocess calls and existing test durations measured; no environment/stdin/output capture in trace','Parallel test durations and nested subprocess timings overlap; do not add them to phase totals','One run per platform, not a stable performance benchmark','Local pinned dependencies preinstalled; Linux dependency fetch/setup timed separately','Instrumentation and analysis are isolated from main; release archive unchanged']};
writeFileSync('reports/release-timing-summary.json',JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({platforms:platforms.map(p=>({name:p.name,total:p.totalSeconds,phases:p.phases,negativeCompilation:p.negativeCompilation})),workflow},null,2));
