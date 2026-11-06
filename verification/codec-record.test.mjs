import assert from 'node:assert/strict';
import test from 'node:test';
import {cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import * as e from '../build/dev/javascript/gargamelle/gargamelle/encoding.mjs';
import * as fixtures from '../build/dev/javascript/gargamelle/codec_record_test.mjs';
import {s, unwrap} from './generated-api.mjs';
import {compileOracle} from './oracle.mjs';
import {compileSupplementary} from './supplementary-oracle.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
function run(args, cwd) {
  const result = spawnSync('gleam', args, {cwd, encoding: 'utf8', timeout: 60000});
  assert.ifError(result.error);
  return {...result, output: result.stdout + result.stderr};
}

test('paired record schemas agree with independent validators for both policies', async () => {
  for (const policy of [s.RecordPolicy$Strict$const, s.RecordPolicy$Open$const]) {
    const codec = unwrap(fixtures.person_codec(policy));
    const definition = s.contract_definition(e.contract(codec));
    const schema = JSON.parse(s.schema_string(definition, s.JsonLayout$Compact$const));
    const validators = [compileOracle(schema), await compileSupplementary(schema)];
    for (const input of [
      {name: 'Azrael'}, {name: 'A', nickname: null},
      {name: 'A', nickname: 'Z', active: false}, {name: 'A', extra: 42},
      {}, [], null, {name: false}, {name: 'A', nickname: 1},
      {name: 'A', active: null},
    ]) {
      const json = unwrap(s.parse(JSON.stringify(input)));
      const accepted = s.validate(definition, json).isOk();
      for (const validate of validators) {
        assert.equal(validate(input).accepted, accepted, JSON.stringify(input));
      }
    }
  }
});

test('paired records retain static types, compile the guide, and short-circuit on both targets', () => {
  const directory = mkdtempSync(join(tmpdir(), 'gargamelle-codec-record-'));
  try {
    const library = join(directory, 'library');
    mkdirSync(library);
    cpSync(join(root, 'src'), join(library, 'src'), {recursive: true});
    cpSync(join(root, 'gleam.toml'), join(library, 'gleam.toml'));
    const consumer = join(directory, 'consumer');
    mkdirSync(join(consumer, 'src'), {recursive: true});
    writeFileSync(join(consumer, 'gleam.toml'), `name = "codec_probe"
version = "0.1.0"
[dependencies]
gargamelle = { path = "../library" }
gleam_stdlib = { path = ${JSON.stringify(join(root, 'build/packages/gleam_stdlib'))} }
gleam_json = { path = ${JSON.stringify(join(root, 'build/packages/gleam_json'))} }
`);
    const probe = join(consumer, 'src/codec_probe.gleam');
    const guide = readFileSync(join(root, 'docs/encoding.md'), 'utf8').split('## Shared record declarations')[1];
    const example = guide.match(/```gleam\n([\s\S]*?)\n```/)[1];
    const expected = guide.match(/```text\n([\s\S]*?)\n```/)[1];
    const prefix = `import gargamelle as g
import gargamelle/codec_record as c
import gargamelle/encoding as e
import gargamelle/record
import gleam/option.{type Option, None}
fn text() { e.codec(e.string(), g.contract(g.string())) }
`;
    const negatives = [
      ['incomplete constructor', `pub fn main() {
        c.start(record.start2(fn(a, b) { #(a, b) }))
        |> c.required("a", text(), fn(v: #(String, Int)) { v.0 })
        |> c.finish(g.Strict)
      }`],
      ['wrong getter result', `pub fn main() {
        c.start(record.start1(fn(a) { a }))
        |> c.required("a", text(), fn(_: String) { True })
        |> c.finish(g.Strict)
      }`],
      ['optional needs Option', `pub fn main() {
        c.start(record.start1(fn(a) { a }))
        |> c.optional("a", text(), fn(v: String) { v })
        |> c.finish(g.Strict)
      }`],
      ['defaulted getter mismatch', `pub fn main() {
        c.start(record.start1(fn(a) { a }))
        |> c.defaulted("a", text(), g.json_null(), fn(_: String) { 1 })
        |> c.finish(g.Strict)
      }`],
      ['incompatible whole type', `pub fn main() {
        c.start(record.start1(fn(a) { [a] }))
        |> c.required("a", text(), fn(v: String) { v })
        |> c.finish(g.Strict)
      }`],
      ['construction environment must be complete', `pub fn main() {
        let builder: Result(g.Record(fn(String) -> String, Int), g.DefinitionError) = record.start1(fn(v) { v })
        c.start(builder)
      }`],
    ];
    const corePath = join(library, 'src/gargamelle.gleam');
    const encoderPath = join(library, 'src/gargamelle/encoding.gleam');
    const core = readFileSync(corePath, 'utf8');
    const encoder = readFileSync(encoderPath, 'utf8');
    function poison(source, names) {
      for (const name of names) {
        const header = new RegExp(`pub fn ${name}\\([\\s\\S]*?\\{\\n`);
        assert.match(source, header);
        source = source.replace(header, '$&  panic as "builder operation invoked"\n');
      }
      return source;
    }
    for (const target of ['javascript', 'erlang']) {
      writeFileSync(corePath, core);
      writeFileSync(encoderPath, encoder);
      writeFileSync(probe, example);
      let result = run(['run', '--target', target], consumer);
      assert.equal(result.status, 0, result.output);
      assert.equal(result.stdout.trim(), expected);
      for (const [name, body] of negatives) {
        writeFileSync(probe, prefix + body);
        result = run(['build', '--target', target], consumer);
        assert.notEqual(result.status, 0, `${target}: ${name} unexpectedly compiled`);
        assert.match(result.output, /Type mismatch/, `${name}\n${result.output}`);
      }
      writeFileSync(corePath, poison(core, ['required', 'optional', 'defaulted', 'finish', 'contract_requirements', 'contract_definition']));
      writeFileSync(encoderPath, poison(encoder, ['field', 'optional_field', 'finish', 'encoder']));
      writeFileSync(probe, prefix + `import gleam/io
pub fn main() {
  let cause = g.DefinitionError("first failure")
  let failed: Result(g.Record(fn(String) -> fn(Option(String)) -> fn(String) -> String, Nil), g.DefinitionError) = Error(cause)
  let result = c.start(failed)
    |> c.required("a", text(), fn(v) { v })
    |> c.optional("b", text(), fn(_) { None })
    |> c.defaulted("c", text(), g.json_null(), fn(v) { v })
    |> c.finish(g.Strict)
  let assert Error(c.Definition(error)) = result
  let assert True = error == cause
  io.println("short circuit passed")
}`);
      result = run(['run', '--target', target], consumer);
      assert.equal(result.status, 0, result.output);
      assert.equal(result.stdout.trim(), 'short circuit passed');
      // Positive control: the same instrumentation must fail for a live builder.
      writeFileSync(probe, prefix + `pub fn main() {
        c.start(record.start1(fn(a) { a }))
        |> c.required("a", text(), fn(v: String) { v })
        |> c.finish(g.Strict)
      }`);
      result = run(['run', '--target', target], consumer);
      assert.notEqual(result.status, 0, result.output);
      assert.match(result.output, /builder operation invoked/, result.output);
    }
  } finally {
    rmSync(directory, {recursive: true, force: true});
  }
});
