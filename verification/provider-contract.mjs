// Isolated integration with an explicitly supplied consumer checkout.
// No consumer source, dependency pins or production artifacts are modified.
import assert from 'node:assert/strict';
import {cpSync,mkdtempSync,mkdirSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const root=fileURLToPath(new URL('../',import.meta.url));
if(!process.argv[2])throw new Error('Usage: node verification/provider-contract.mjs /path/to/equation-flashcards');
const app=resolve(process.argv[2]);
const provider=readFileSync(join(app,'boundaries/src/providers_cloze.gleam'),'utf8');
const normalization=readFileSync(join(app,'providers/cloze/normalization.js'),'utf8');
const directory=mkdtempSync(join(tmpdir(),'gargamelle-provider-contract-'));
try {
  const library=join(directory,'library');
  mkdirSync(library);
  for(const name of ['src','priv','gleam.toml'])cpSync(join(root,name),join(library,name),{recursive:true});
  mkdirSync(join(directory,'src'));
  const dependency=(name,path)=>`${name} = { path = ${JSON.stringify(path)} }\n`;
  writeFileSync(join(directory,'gleam.toml'),'name = "provider_contract"\nversion = "0.1.0"\ntarget = "javascript"\n[dependencies]\n'+dependency('gargamelle',library)+dependency('gleam_stdlib',join(root,'build/packages/gleam_stdlib'))+dependency('gleam_json',join(root,'build/packages/gleam_json')));
  // Migration in the temporary copy only: old boundary constructors receive a
  // structural Contract. Probe contracts below move the real semantic checks
  // before handler invocation instead of leaving them in legacy handlers.
  let migrated=provider.replaceAll('../../../../../providers/cloze/normalization.js','./normalization.mjs');
  migrated=migrated.replace(/schema\.boundary\(([^\n]*?), fn/g,(_match,definition)=>`schema.boundary(schema.contract(${definition}), fn`);
  writeFileSync(join(directory,'src/providers_cloze.gleam'),migrated);
  writeFileSync(join(directory,'src/normalization.mjs'),normalization);
  writeFileSync(join(directory,'src/provider_contract.gleam'),`import gargamelle as s
import gleam/io
import gleam/result
import providers_cloze as provider

fn violations(error: String) { [s.Violation("", error)] }

pub fn historical_contract() {
  s.contract(provider.result_definition())
  |> s.require("Historical evidence agrees with recorded alternatives and totals", fn(evidence) {
    provider.validate_evidence(evidence)
    |> result.map(fn(_) { Nil })
    |> result.map_error(violations)
  })
}

pub fn current_contract(card: provider.Content) {
  historical_contract()
  |> s.require("New evidence agrees with the current card", fn(evidence) {
    // The current-card part is independent of historical acceptance. This
    // adapter exercises the existing combined validator; provider migration
    // should split its checks rather than repeat the historical predicate.
    provider.validate_evidence_for(evidence, card)
    |> result.map(fn(_) { Nil })
    |> result.map_error(violations)
  })
}

pub fn main() {
  let original = "{\\\"type\\\":\\\"cloze\\\",\\\"version\\\":1,\\\"data\\\":{\\\"entries\\\":[{\\\"blankId\\\":\\\"a\\\",\\\"response\\\":\\\"old\\\",\\\"accepted\\\":[\\\"old\\\"],\\\"correct\\\":true}],\\\"correct\\\":1,\\\"total\\\":1}}"
  let inconsistent = "{\\\"type\\\":\\\"cloze\\\",\\\"version\\\":1,\\\"data\\\":{\\\"entries\\\":[{\\\"blankId\\\":\\\"a\\\",\\\"response\\\":\\\"old\\\",\\\"accepted\\\":[\\\"old\\\"],\\\"correct\\\":true}],\\\"correct\\\":0,\\\"total\\\":1}}"
  let assert Ok(json) = s.parse(original)
  let assert Ok(bad) = s.parse(inconsistent)
  let old_card = provider.Content("card", "Title", "Prompt", 1, [provider.BlankRef("a")], [provider.Blank("a", "A", ["old"])])
  let new_card = provider.Content("card", "Title", "Prompt", 2, [provider.BlankRef("a")], [provider.Blank("a", "A", ["new"])])
  let historical = historical_contract()
  let historical_receiver = s.json_boundary(historical, fn(verified) { s.verified_json(verified) })
  let assert Ok(accepted) = s.forward_json(historical_receiver, json)
  let assert True = accepted == json
  let assert Ok(_) = s.validate(provider.result_definition(), bad)
  let assert Error(s.Semantic(_)) = s.forward_json(historical_receiver, bad)
  let assert Ok(_) = s.forward_json(s.json_boundary(current_contract(old_card), s.verified_json), json)
  let assert Error(s.Semantic(_)) = s.forward_json(s.json_boundary(current_contract(new_card), s.verified_json), json)
  // Updated content does not change the permanent historical contract.
  let assert Ok(certificate) = s.verify(historical, json)
  let assert Error(s.Semantic(_)) = s.forward_json(s.json_boundary(current_contract(new_card), s.verified_json), s.verified_json(certificate))
  let assert Ok(_) = s.forward(s.boundary(historical, fn(data, _) { data }), json)
  io.println("provider contract integration passed")
}
`);
  const run=spawnSync('gleam',['run'],{cwd:directory,encoding:'utf8',timeout:60000,maxBuffer:5*1024*1024});
  assert.equal(run.status,0,run.stdout+run.stderr);
  assert.equal(run.stdout,'provider contract integration passed\n');
  const digest=text=>createHash('sha256').update(text).digest('hex');
  console.log(JSON.stringify({status:'passed',consumer:app,providerSha256:digest(provider),normalizationSha256:digest(normalization),checks:['historical acceptance','semantic inconsistency rejected before handler','current context accepted','changed context rejected','historical context preserved','foreign certificate rechecked','typed receiver acceptance'],limitations:['JavaScript-only consumer','temporary API migration','combined current-card validator repeats historical predicate internally'],consumerChanged:false},null,2));
} finally { rmSync(directory,{recursive:true,force:true}); }
