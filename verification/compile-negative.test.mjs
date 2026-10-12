import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync,mkdirSync,writeFileSync,rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join,resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const root=fileURLToPath(new URL('../',import.meta.url));
const cases=[
 ['opaque_encoder','pub fn main() { e.Plan(fn(_,_) { Ok(Nil) }) }','Unknown module value'],
 ['open_encoder_not_executable','pub fn main() { e.recursive(fn(self) { e.encode_json(self,"x") Ok(self) }) }','Type mismatch'],
 ['wrong_codec_output_type','pub fn main() { e.codec(e.text(), s.contract(s.safe_integer())) }','Type mismatch'],
 ['wrong_output_receiver_type','pub fn main() { e.output_boundary(e.text(), s.json_boundary(s.contract(s.safe_integer()), fn(x) { x })) }','Type mismatch'],
 ['private_output_handler','pub fn main() { e.output_boundary(e.text(),s.json_boundary(s.contract(s.text()),fn(x) { x })).handler }','Unknown record field'],
 ['wrong_encoder_getter','pub fn main() { e.field(e.record(),"count",e.safe_integer(),fn(_: String) { "wrong" }) }','Type mismatch'],

 ['opaque_json_boundary','pub fn main() { s.JsonBoundary(s.text(), fn(x) { x }) }','Unknown module value'],
 ['private_contract','pub fn main() { s.Contract(s.text(), []) }','Unknown module value'],
 ['definition_not_boundary_contract','pub fn main() { s.boundary(s.text(), fn(data, _) { data }) }','Type mismatch'],
 ['definition_not_verification_contract','pub fn main() { let assert Ok(json) = s.parse("null") s.verify(s.text(), json) }','Type mismatch'],
 ['requirement_cannot_transform','pub fn main() { s.require(s.contract(s.text()), "Transform", fn(text) { Ok(text) }) }','Type mismatch'],
 ['certificate_not_json_submission','pub fn main(v: s.VerifiedJson(String)) { s.forward_json(s.json_boundary(s.contract(s.text()), fn(x) { x }), v) }','Type mismatch'],
 ['json_boundary_handler_type','pub fn main() { s.json_boundary(s.contract(s.text()), fn(x: s.VerifiedJson(Int)) { x }) }','Type mismatch'],
 ['private_json_handler','pub fn main() { s.json_boundary(s.contract(s.text()), fn(x) { x }).handler }','Unknown record field'],
 ['opaque_verified_json','pub fn main() { let assert Ok(v) = s.parse("null") s.VerifiedJson(v, Nil) }','Unknown module value'],
 ['opaque_boundary','pub fn main() { s.Boundary(s.text(), fn(x, _) { x }) }','Unknown module value'],
 ['verified_not_forward_input','pub fn main(v: s.VerifiedJson(String)) { s.forward(s.boundary(s.contract(s.text()), fn(data, _) { data }), v) }','Type mismatch'],
 ['boundary_handler_output_type','pub fn main() { s.boundary(s.contract(s.text()), fn(v: Int, _) { v }) }','Type mismatch'],
 ['private_boundary_handler','pub fn main() { let b = s.boundary(s.contract(s.text()), fn(data, _) { data }) b.handler }','Unknown record field'],
 ['removed_verified_data','pub fn main(v: s.VerifiedJson(String)) { s.verified_data(v) }','Unknown module value'],
 ['old_boundary_handler','pub fn main() { s.boundary(s.contract(s.text()), fn(x) { x }) }','Type mismatch'],
 ['missing_json_format','pub fn main() { let assert Ok(v) = s.parse("null") s.to_string(v) }','Incorrect arity'],
 ['missing_schema_format','pub fn main() { s.schema_string(s.text()) }','Incorrect arity'],
 ['removed_value_type','pub fn main(value: s.Value) { value }','Unknown module type'],
 ['removed_policy_type','pub fn main(policy: s.Policy) { policy }','Unknown module type'],
 ['removed_closed','pub fn main() { s.Closed }','Unknown module value'],
 ['removed_value_text','pub fn main() { s.value_text(Nil) }','Unknown module value'],
 ['removed_emit_json','pub fn main() { s.emit_json(s.text()) }','Unknown module value'],
 ['removed_emit_text','pub fn main() { s.emit_text(s.text()) }','Unknown module value'],
 ['foreign_json_type','import gleam/json\npub fn main() -> s.Json { json.string("not admitted") }','Type mismatch'],
 ['opaque_json_constructor','pub fn main() { s.Json("unadmitted") }','Unknown module value'],
 ['exclusion_output_type','pub fn main() -> s.Definition(String) { s.exclude(s.number(),s.text()) }','Type mismatch'],
 ['conditional_output_type','pub fn main() -> s.Definition(String) { s.if_then(s.number(),s.text(),s.boolean()) }','Type mismatch'],
 ['private_condition','pub fn main() { s.Condition(Nil,Nil,gleam_option.None) }','Unknown module value'],
 ['membership_count_type','pub fn main() { s.contains(s.array(s.text()),s.text(),True,gleam_option.None) }','Type mismatch'],
 ['key_definition_type','pub fn main() { s.property_names(s.dictionary(s.text()),s.number()) }','Type mismatch'],
 ['tuple_position_type','pub fn main() { s.element(s.tuple(fn(x: Int){x}),s.text()) }','Type mismatch'],
 ['opaque_tuple','pub fn main() { s.Tuple([],fn(x){x}) }','Unknown module value'],
 ['recursive_output_type','pub fn main() { s.recursive("tree",fn(self: s.Plan(Int, s.Recursive(Int))) { Ok(s.text()) }) }','Type mismatch'],
 ['mutual_output_types','pub fn main() { s.recursive_pair("a","b",fn(a: s.Plan(Int, #(s.Recursive(Int), s.Recursive(String))),b: s.Plan(String, #(s.Recursive(Int), s.Recursive(String)))) { Ok(#(b,a)) }) }','Type mismatch'],
 ['private_reference_node','pub fn main() { s.ReferenceNode("tree",Nil) }','Unknown module value'],
 ['private_recursion_runner','pub fn main() { s.Recursive(fn(_,_) { Nil }) }','Unknown module value'],
 ['open_plan_decode','pub fn main() { let assert Ok(v) = s.parse("[]") s.recursive("tree",fn(self) { s.decode(self,v) Ok(self) }) }','Type mismatch'],
 ['open_plan_validate','pub fn main() { let assert Ok(v) = s.parse("[]") s.recursive("tree",fn(self) { s.validate(self,v) Ok(self) }) }','Type mismatch'],
 ['open_plan_verify','pub fn main() { let assert Ok(v) = s.parse("[]") s.recursive("tree",fn(self) { s.verify(s.contract(self),v) Ok(self) }) }','Type mismatch'],
 ['open_plan_emit','pub fn main() { s.recursive("tree",fn(self) { s.schema_string(self, s.Compact) Ok(self) }) }','Type mismatch'],
 ['open_plan_render','pub fn main() { s.recursive("tree",fn(self) { documentation.render(self,"tree") Ok(self) }) }','Type mismatch'],
 ['opaque_plan','pub fn main() { s.Plan(Nil, fn(_,_,_) { Nil }) }','Unknown module value'],
 ['private_evidence','pub fn main() { s.Atomic }','Unknown module value'],
 ['float_is_not_int','pub fn main() -> s.Definition(Int) { s.number() }','Type mismatch'],
 ['float_bounds_not_int','pub fn main() { s.number_bounds(s.safe_integer(), gleam_option.None, gleam_option.None) }','Type mismatch'],
 ['opaque_definition','pub fn main() { s.Definition(Nil, fn(x) {x}) }','Unknown module value'],
 ['opaque_input','pub fn main() { s.JString("unadmitted") }','Unknown module value'],
 ['wrapped_tagged_branch','pub fn main() { let wrapped = s.description(s.finish(s.record(Nil),s.Strict),"x") s.variant("x",wrapped,s.Strict) }','Type mismatch'],
 ['mapped_tagged_branch','pub fn main() { let wrapped = s.map(s.finish(s.record(Nil),s.Strict),fn(x){x}) s.variant("x",wrapped,s.Strict) }','Type mismatch'],
 ['nonrecord_tagged_branch','pub fn main() { s.variant("x",s.text(),s.Strict) }','Type mismatch'],
 ['optional_is_option','pub fn main() { s.optional(s.record(fn(x: String){x}),"x",s.text()) }','Type mismatch'],
 ['no_predicate_escape','pub fn main() { s.predicate(s.text(),fn(_){False}) }','Unknown module value'],
];
test(`compile-time boundary on both targets: positive baseline and ${cases.length} forbidden API programs`,()=>{
 const dir=mkdtempSync(join(tmpdir(),'schema-contract-negative-'));
 try{
 mkdirSync(join(dir,'src'));
 const q=p=>JSON.stringify(p);
 writeFileSync(join(dir,'gleam.toml'),`name = "negative_probe"\nversion = "0.1.0"\ntarget = "javascript"\n[dependencies]\ngargamelle = { path = ${q(root)} }\ngleam_stdlib = { path = ${q(resolve(root,'build/packages/gleam_stdlib'))} }\ngleam_json = { path = ${q(resolve(root,'build/packages/gleam_json'))} }\n`);
 const compile=(body,target)=>{writeFileSync(join(dir,'src/negative_probe.gleam'),'import gargamelle as s\nimport gargamelle/encoding as e\nimport gargamelle/documentation\nimport gleam/option as gleam_option\n'+body+'\n');const run=spawnSync('gleam',['build','--target',target],{cwd:dir,encoding:'utf8',timeout:30000});if(run.error)throw run.error;return {status:run.status,output:run.stdout+run.stderr};};
 for(const target of ['javascript','erlang']){
 const positive=compile('pub fn main() { s.variant("x",s.record(Nil),s.Strict) }',target);
 assert.equal(positive.status,0,positive.output);
 for(const [name,body,diagnostic] of cases){const result=compile(body,target);assert.notEqual(result.status,0,target+': '+name);assert.match(result.output,new RegExp(diagnostic),target+': '+name+'\n'+result.output);}
 }
 }finally{rmSync(dir,{recursive:true,force:true});}
});
