// Isolated integration with explicitly supplied authoritative provider sources.
// No consumer source, dependency pin or production artifact is modified.
import assert from 'node:assert/strict';
import {cpSync,mkdtempSync,mkdirSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {compileOracle} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';
const root=fileURLToPath(new URL('../',import.meta.url));
if(!process.argv[2])throw new Error('Usage: node verification/provider-contract.mjs /path/to/equation-flashcards');
const app=resolve(process.argv[2]),sources={};
const digest=text=>createHash('sha256').update(text).digest('hex');
const directory=mkdtempSync(join(tmpdir(),'gargamelle-provider-contract-'));
const providers=['cloze','diagram-labeling','equation','verbatim','self-review'];
try {
  const library=join(directory,'library');
  mkdirSync(library);
  for(const name of ['src','priv','gleam.toml'])cpSync(join(root,name),join(library,name),{recursive:true});
  mkdirSync(join(directory,'src'));
  const dependency=(name,path)=>`${name} = { path = ${JSON.stringify(path)} }\n`;
  writeFileSync(join(directory,'gleam.toml'),'name = "provider_contract"\nversion = "0.1.0"\ntarget = "javascript"\n[dependencies]\n'+dependency('gargamelle',library)+dependency('gleam_stdlib',join(root,'build/packages/gleam_stdlib'))+dependency('gleam_json',join(root,'build/packages/gleam_json')));
  for(const id of providers){
    const path=`providers/${id}/contracts.gleam`,original=readFileSync(join(app,path),'utf8');
    sources[path]=digest(original);
    let migrated=original.replaceAll('../../../../../providers/cloze/normalization.js','./normalization.mjs').replace('import app_gargamelle_boundary as gargamelle_boundary','import gargamelle/boundary as gargamelle_boundary');
    // Adapt only temporary legacy boundary callers. Contract adapters exercise
    // the real provider predicates before handlers, separately from these callers.
    migrated=migrated.replace(/(schema|s)\.boundary\(([^\n]*?), fn/g,(match,alias,definition)=>/_definition\(/.test(definition)?`${alias}.boundary(${alias}.contract(${definition}), fn`:match);
    if(id==='cloze'){
      const combined='  use e <- result.try(validate_evidence(e))\n  case';
      assert.ok(migrated.includes(combined),'Cloze semantic split anchor changed');
      migrated=migrated.replace(combined,'  use e <- result.try(validate_evidence(e))\n  validate_evidence_context(e, card)\n}\n\npub fn validate_evidence_context(e: Evidence, card: Content) {\n  case');
    }
    if(id==='diagram-labeling'){
      const combined='  use value <- result.try(validate_result(value))\n  case';
      assert.ok(migrated.includes(combined),'Diagram semantic split anchor changed');
      migrated=migrated.replace(combined,'  use value <- result.try(validate_result(value))\n  validate_result_context(value, targets, labels)\n}\n\npub fn validate_result_context(value: Evidence, targets: List(#(String, String)), labels: List(String)) {\n  case');
    }
    writeFileSync(join(directory,'src',`providers_${id.replaceAll('-','_')}.gleam`),migrated);
  }
  const normalization=readFileSync(join(app,'providers/cloze/normalization.js'),'utf8');
  sources['providers/cloze/normalization.js']=digest(normalization);
  writeFileSync(join(directory,'src/normalization.mjs'),normalization);
  cpSync(join(root,'verification/providers/contracts.gleam'),join(directory,'src/contract_adapters.gleam'));
  cpSync(join(root,'verification/providers/encoding.gleam'),join(directory,'src/provider_encoding.gleam'));
  const build=spawnSync('gleam',['build'],{cwd:directory,encoding:'utf8',timeout:60000,maxBuffer:5*1024*1024});
  assert.equal(build.status,0,build.stdout+build.stderr);
  const modules=join(directory,'build/dev/javascript');
  const load=(pkg,path)=>import(pathToFileURL(join(modules,pkg,path+'.mjs')));
  const s=await load('gargamelle','gargamelle');
  const b=await load('gargamelle','gargamelle/boundary');
  const adapters=await load('provider_contract','contract_adapters');
  const encoding=await load('gargamelle','gargamelle/encoding');
  const producer=await load('provider_contract','provider_encoding');
  const {toList,Ok}=await load('provider_contract','gleam');
  const compiled=Object.fromEntries(await Promise.all(providers.map(async id=>[id,await load('provider_contract','providers_'+id.replaceAll('-','_'))])));
  const unwrap=result=>{assert.ok(result.isOk(),JSON.stringify(result));return result[0];};
  const admitted=raw=>unwrap(s.parse(JSON.stringify(raw)));
  const checks=[];
  const run=async(name,contract,cases)=>{
    const definition=s.contract_definition(contract);
    const schema=JSON.parse(s.schema_string(definition,s.JsonFormat$Compact$const));
    const oracles=[compileOracle(schema),await compileSupplementary(schema)];
    let handled=0;
    const receiver=b.json_boundary(contract,verified=>{handled++;return s.verified_json(verified);});
    const typed=b.boundary(contract,(_value,json)=>json);
    for(const {json:raw,accepted,structural=true} of cases){
      const json=admitted(raw),before=handled;
      for(const oracle of oracles)assert.equal(oracle(raw).accepted,structural,name+' schema acceptance');
      const result=b.forward_json(receiver,json),data=b.forward(typed,json);
      assert.equal(result.isOk(),accepted,name+' JSON receiver');
      assert.equal(data.isOk(),accepted,name+' typed receiver');
      assert.equal(handled-before,accepted?1:0,name+' handler count');
      if(accepted){assert.equal(result[0],json);assert.equal(data[0],json);}
      else assert.equal(result[0].constructor.name,structural?'Semantic':'Structural',name+' diagnostic class');
    }
    checks.push({name,cases:cases.length,requirements:[...s.contract_requirements(contract)]});
  };
  const cloze={type:'cloze',version:1,data:{entries:[{blankId:'a',response:'old',accepted:['old'],correct:true}],correct:1,total:1}};
  const inconsistent=structuredClone(cloze);inconsistent.data.correct=0;
  const oldCard=new compiled.cloze.Content('card','Title','Prompt',1,toList([new compiled.cloze.BlankRef('a')]),toList([new compiled.cloze.Blank('a','A',toList(['old']))]));
  const newCard=new compiled.cloze.Content('card','Title','Prompt',2,toList([new compiled.cloze.BlankRef('a')]),toList([new compiled.cloze.Blank('a','A',toList(['new']))]));
  await run('cloze historical',adapters.cloze_historical(),[{json:cloze,accepted:true},{json:inconsistent,accepted:false},{json:{},accepted:false,structural:false}]);
  await run('cloze current',adapters.cloze_current(oldCard),[{json:cloze,accepted:true},{json:inconsistent,accepted:false}]);
  await run('cloze changed context',adapters.cloze_current(newCard),[{json:cloze,accepted:false}]);
  await run('cloze session',adapters.cloze_session('old',toList(['a'])),[{json:{clozeSignature:'old',responses:{a:'answer'}},accepted:true},{json:{clozeSignature:'new',responses:{a:'answer'}},accepted:false},{json:{clozeSignature:'old',responses:{unknown:'answer'}},accepted:false}]);
  const diagram={type:'diagram-labeling',version:1,data:{entries:[{targetId:'t',expectedLabelId:'l',labelId:'l',correct:true}],correct:1,total:1}};
  const badDiagram=structuredClone(diagram);badDiagram.data.correct=0;
  await run('diagram historical',adapters.diagram_historical(),[{json:diagram,accepted:true},{json:badDiagram,accepted:false},{json:{},accepted:false,structural:false}]);
  await run('diagram current',adapters.diagram_current(toList([['t','l']]),toList(['l'])),[{json:diagram,accepted:true},{json:badDiagram,accepted:false}]);
  await run('diagram changed context',adapters.diagram_current(toList([['t','new']]),toList(['new'])),[{json:diagram,accepted:false}]);
  await run('diagram session',adapters.diagram_session('old',toList(['t']),toList(['l'])),[{json:{diagramSignature:'old',placements:{t:'l'}},accepted:true},{json:{diagramSignature:'new',placements:{t:'l'}},accepted:false},{json:{diagramSignature:'old',placements:{unknown:'l'}},accepted:false}]);
  for(const [id,raw] of [['equation',{type:'equation',version:1,data:{outcome:'solved'}}],['self-review',{type:'self-review',version:1,data:{rating:'good'}}]])
    await run(id+' result',s.contract(compiled[id].result_definition()),[{json:raw,accepted:true},{json:{},accepted:false,structural:false}]);
  for(const version of [1,2,3]){
    const raw={type:'verbatim',version,data:{warnings:1,peeks:0,answerShown:false,...(version>1?{multiplier:3}:{}),...(version===3?{answerReveals:0}:{})}};
    await run('verbatim v'+version,s.contract(compiled.verbatim.result_definition()),[{json:raw,accepted:true},{json:{},accepted:false,structural:false}]);
  }
  // Structural certificates and historical certificates cannot bypass current
  // requirements. Neither changes the historical contract's captured authority.
  for(const [raw,historical,current] of [[cloze,adapters.cloze_historical(),adapters.cloze_current(newCard)],[diagram,adapters.diagram_historical(),adapters.diagram_current(toList([['t','new']]),toList(['new']))]]){
    const certificate=unwrap(s.verify(historical,admitted(raw)));
    const receiver=b.json_boundary(current,()=>{throw Error('Rejected certificate reached handler');});
    assert.equal(b.forward_json(receiver,s.verified_json(certificate)).isOk(),false);
    assert.ok(s.verify(s.verified_contract(certificate),s.verified_json(certificate)).isOk());
    const weak=unwrap(s.verify(s.contract(s.contract_definition(current)),admitted(raw)));
    assert.equal(b.forward_json(receiver,s.verified_json(weak)).isOk(),false);
  }
  // Ensure the independently split current checks are reported separately.
  const combined=b.forward_json(b.json_boundary(adapters.cloze_current(newCard),s.verified_json),admitted(inconsistent));
  assert.deepEqual([...combined[0][0]].map(failure=>failure.index),[0,1]);
  const typedEvidence=new compiled.cloze.Evidence(toList([new compiled.cloze.Entry('a','old',toList(['old']),true)]),1,1);
  const typedInconsistent=new compiled.cloze.Evidence(typedEvidence.entries,0,1);
  let encoded=0,verified=0,stored=0;
  const encoder=encoding.contramap(producer.cloze_encoder(),value=>{encoded++;return value;});
  const receiving=s.require(compiled.cloze.evidence_for_contract(oldCard),'Observe verification',()=>{verified++;return new Ok(undefined);});
  const output=b.output_boundary(encoder,b.json_boundary(receiving,certificate=>{stored++;return s.verified_json(certificate);}));
  const emitted=unwrap(b.send(output,typedEvidence));
  assert.deepEqual(JSON.parse(s.to_string(emitted,s.JsonFormat$Compact$const)),cloze);
  assert.deepEqual([encoded,verified,stored],[1,1,1]);
  const schema=JSON.parse(s.schema_string(s.contract_definition(b.output_contract(output)),s.JsonFormat$Compact$const));
  for(const oracle of [compileOracle(schema),await compileSupplementary(schema)])assert.equal(oracle(cloze).accepted,true);
  const rejected=b.send(output,typedInconsistent);
  assert.equal(rejected.isOk(),false);assert.equal(rejected[0].constructor.name,'Contract');
  assert.equal(rejected[0][0].constructor.name,'Semantic');
  assert.deepEqual([encoded,verified,stored],[2,2,1]);
  const changed=b.output_boundary(producer.cloze_encoder(),b.json_boundary(compiled.cloze.evidence_for_contract(newCard),()=>{throw Error('Changed-context output reached storage');}));
  assert.equal(b.send(changed,typedEvidence).isOk(),false);
  const historical=b.output_boundary(producer.cloze_encoder(),b.json_boundary(compiled.cloze.evidence_contract(),s.verified_json));
  assert.equal(b.send(historical,typedEvidence).isOk(),true);
  const unsafe=new compiled.cloze.Evidence(typedEvidence.entries,9007199254740992,1);
  const primitive=b.send(output,unsafe);
  assert.equal(primitive.isOk(),false);assert.equal(primitive[0].path,'/data/correct');
  assert.deepEqual([encoded,verified,stored],[3,2,1]);
  checks.push({name:'typed cloze output',cases:5,requirements:[...s.contract_requirements(receiving)],encodingCallsPerSubmission:1,contractChecksPerAdmittedSubmission:1,rejectionSkipsStorage:true});
  for(const [path,hash] of Object.entries(sources))assert.equal(digest(readFileSync(join(app,path),'utf8')),hash,'Consumer source changed: '+path);
  const report={status:'passed',sources,checks,certificateRechecks:4,consumerChanged:false,limitations:['JavaScript consumer; provider sources are migrated in a temporary copy','Provider adapters are integration evidence, not shipped Gargamelle API']};
  mkdirSync(join(root,'reports'),{recursive:true});
  writeFileSync(join(root,'reports/provider-contract-integration.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report,null,2));
} finally { rmSync(directory,{recursive:true,force:true}); }
