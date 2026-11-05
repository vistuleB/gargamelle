import assert from 'node:assert/strict';
import test from 'node:test';
import {cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
function run(command, args, cwd = root) {
  const result = spawnSync(command, args, {cwd, encoding: 'utf8', timeout: 60000});
  assert.ifError(result.error);
  return {...result, output: result.stdout + result.stderr};
}

test('record wrappers are reproducibly generated', () => {
  const result = run(process.execPath, ['verification/generate-record.mjs', '--check']);
  assert.equal(result.status, 0, result.output);
});

test('README curried and ordinary constructors have identical schemas, outputs and errors', () => {
  const directory = mkdtempSync(join(tmpdir(), 'gargamelle-readme-record-'));
  try {
    mkdirSync(join(directory, 'src'));
    writeFileSync(join(directory, 'gleam.toml'), `name = "readme_record"
version = "0.1.0"
[dependencies]
gargamelle = { path = ${JSON.stringify(root)} }
gleam_stdlib = { path = ${JSON.stringify(join(root, 'build/packages/gleam_stdlib'))} }
gleam_json = { path = ${JSON.stringify(join(root, 'build/packages/gleam_json'))} }
`);
    const readme = readFileSync(join(root, 'README.md'), 'utf8');
    const snippet = readme.split('## Typed records')[1].match(/```gleam\n([\s\S]*?)\n```/)[1];
    const inputs = [
      {name: 'Brainy', age: 42, active: true},
      {name: 'Jokey', age: 0, active: false},
      {name: 'Brainy', active: true},
      {name: 'Brainy', age: '42', active: true},
      {name: 'Brainy', age: 42, active: null},
      {name: 'Brainy', age: 42, active: true, extra: 1},
      {}, [], null,
    ];
    const comparisons = inputs.map(input => `
let assert Ok(json) = gargamelle.parse(${JSON.stringify(JSON.stringify(input))})
let assert True = gargamelle.decode(curried, json) == gargamelle.decode(pipeline, json)
let assert True = gargamelle.validate(curried, json) == gargamelle.validate(pipeline, json)
`).join('');
    writeFileSync(join(directory, 'src/readme_record.gleam'), 'import gleam/io\n' + snippet + `
pub fn main() {
let curried = curried_user_definition()
let pipeline = user_definition()
let assert True = gargamelle.schema_string(curried, gargamelle.Compact)
  == gargamelle.schema_string(pipeline, gargamelle.Compact)
let assert Ok(User("Brainy", 42, True)) = read_user("{\\\"name\\\":\\\"Brainy\\\",\\\"age\\\":42,\\\"active\\\":true}")
${comparisons}
io.println("README record comparison passed")
}
`);
    for (const target of ['javascript', 'erlang']) {
      const result = run('gleam', ['run', '--target', target], directory);
      assert.equal(result.status, 0, result.output);
      assert.equal(result.stdout.trim(), 'README record comparison passed');
    }
  } finally {
    rmSync(directory, {recursive: true, force: true});
  }
});

test('all arities, consumer-shaped output, static errors and short-circuiting on both targets', () => {
  const directory = mkdtempSync(join(tmpdir(), 'gargamelle-record-'));
  const library = join(directory, 'library');
  const consumer = join(directory, 'consumer');
  try {
    mkdirSync(library);
    cpSync(join(root, 'src'), join(library, 'src'), {recursive: true});
    cpSync(join(root, 'gleam.toml'), join(library, 'gleam.toml'));
    mkdirSync(join(consumer, 'src'), {recursive: true});
    writeFileSync(join(consumer, 'gleam.toml'), `name = "record_probe"
version = "0.1.0"
[dependencies]
gargamelle = { path = "../library" }
gleam_stdlib = { path = ${JSON.stringify(resolve(root, 'build/packages/gleam_stdlib'))} }
gleam_json = { path = ${JSON.stringify(resolve(root, 'build/packages/gleam_json'))} }
`);
    const prefix = 'import gargamelle as s\nimport gargamelle/record\nimport gleam/option.{type Option}\n';
    const args = n => Array.from({length: n}, (_, i) => `a${i + 1}`);
    const start = n => `record.start${n}(fn(${args(n).join(', ')}) { [${args(n).join(', ')}] })`;
    const fields = n => args(n).map((_, i) => `|> record.required("field${i + 1}", s.safe_integer())`).join('\n');
    let positive = prefix + 'import gleam/io\n';
    for (let n = 1; n <= 32; n++) {
      const input = Object.fromEntries(args(n).map((_, i) => [`field${i + 1}`, i + 1]));
      positive += `fn arity${n}() -> s.Definition(List(Int)) {
let assert Ok(definition) = ${start(n)} ${fields(n)} |> record.finish(s.Strict)
definition
}
fn check${n}() {
let assert Ok(json) = s.parse(${JSON.stringify(JSON.stringify(input))})
let assert Ok(values) = s.decode(arity${n}(), json)
let assert True = values == [${Array.from({length: n}, (_, i) => i + 1).join(', ')}]
}
`;
    }
    // Thirteen heterogeneous fields, matching the motivating consumer's shape.
    const specs = [
      ['year', 'Int', 's.safe_integer()', 1970, '1970'],
      ...['M_dep', 'R', 'T', 'B_F', 'C_B', 'C_H'].map((name, i) =>
        [name, 'Float', 'nonnegative()', i + 0.5, `${i}.5`]),
      ...['fed_date', 'deposit_date', 'public_cash_date', 'source_convention', 'vault_cash_method', 'public_cash_method'].map((name, i) =>
        [name, 'String', 's.string()', `value${i}`, `"value${i}"`]),
    ];
    positive += `pub type SourceRow { SourceRow(${specs.map((s, i) => `f${i}: ${s[1]}`).join(', ')}) }
fn nonnegative() -> s.Definition(Float) {
let assert Ok(definition) = s.number_bounds(s.number(), gleam_option.Some(s.Inclusive(0.0)), gleam_option.None)
definition
}
fn row_definition() -> s.Definition(SourceRow) {
let assert Ok(definition) = record.start13(SourceRow)
${specs.map(s => `|> record.required("${s[0]}", ${s[2]})`).join('\n')}
|> record.finish(s.Open)
definition
}
pub fn main() {
${args(32).map((_, i) => `check${i + 1}()`).join('\n')}
let assert Ok(json) = s.parse(${JSON.stringify(JSON.stringify(Object.fromEntries(specs.map(s => [s[0], s[3]]))))})
let assert Ok(row) = s.decode(row_definition(), json)
let assert True = row == SourceRow(${specs.map(s => s[4]).join(', ')})
io.println("all arities and typed SourceRow passed")
}
`;
    positive = 'import gleam/option as gleam_option\n' + positive;
    const negatives = [
      ['wrong required input', 'pub fn main() { record.start1(fn(x: Int) { x }) |> record.required("x", s.string()) }'],
      ['optional requires Option', 'pub fn main() { record.start1(fn(x: String) { x }) |> record.optional("x", s.string()) }'],
      ['wrong default child', 'pub fn main() { record.start1(fn(x: Int) { x }) |> record.defaulted("x", s.string(), s.json_null()) }'],
      ['incomplete typed output', 'pub fn main() -> Result(s.Definition(Int), s.DefinitionError) { record.start2(fn(a: Int, b: Int) { a + b }) |> record.required("a", s.safe_integer()) |> record.finish(s.Strict) }'],
      ['too many fields', 'pub fn main() { record.start1(fn(x: Int) { x }) |> record.required("a", s.safe_integer()) |> record.required("b", s.safe_integer()) }'],
      ['wrong constructor arity', 'pub fn main() { record.start2(fn(x: Int) { x }) }'],
      ['upper boundary incomplete', `pub fn main() -> Result(s.Definition(List(Int)), s.DefinitionError) { ${start(32)} ${fields(31)} |> record.finish(s.Strict) }`],
      ['upper boundary wrong arity', `pub fn main() { record.start32(fn(${args(31).join(', ')}) { [${args(31).join(', ')}] }) }`],
      ['construction is not decoding error', 'pub fn main() -> Result(s.Definition(String), List(s.ValidationError)) { record.start1(fn(x) { x }) |> record.required("x", s.string()) |> record.finish(s.Strict) }'],
      ['open recursion cannot escape', 'pub fn main() { s.recursive("tree", fn(self) { let assert Ok(definition) = record.start1(fn(x) { x }) |> record.required("child", self) |> record.finish(s.Strict) s.validate(definition, s.json_null()) Ok(self) }) }'],
    ];
    const guide = readFileSync(join(root, 'docs/advanced.md'), 'utf8')
      .split('## Pipe-friendly record construction')[1].split('## Schema annotations')[0];
    const guideSource = guide.match(/```gleam\n([\s\S]*?)\n```/)[1];
    const guideOutput = guide.match(/```text\n([\s\S]*?)\n```/)[1];
    const probe = join(consumer, 'src/record_probe.gleam');
    const coreFile = join(library, 'src/gargamelle.gleam');
    const core = readFileSync(coreFile, 'utf8');
    for (const target of ['javascript', 'erlang']) {
      writeFileSync(coreFile, core);
      writeFileSync(probe, positive);
      let result = run('gleam', ['run', '--target', target], consumer);
      assert.equal(result.status, 0, result.output);
      assert.equal(result.stdout.trim(), 'all arities and typed SourceRow passed');
      writeFileSync(probe, guideSource);
      result = run('gleam', ['run', '--target', target], consumer);
      assert.equal(result.status, 0, result.output);
      assert.equal(result.stdout.trim(), guideOutput);
      for (const [name, body] of negatives) {
        writeFileSync(probe, prefix + body);
        result = run('gleam', ['build', '--target', target], consumer);
        assert.notEqual(result.status, 0, `${target}: ${name} unexpectedly compiled`);
        assert.match(result.output, /Type mismatch|Incorrect arity/, `${target}: ${name}\n${result.output}`);
      }
      // Make each underlying operation observably fail if called. The public
      // helper must return the supplied error without reaching any of them.
      let instrumented = core;
      for (const name of ['required', 'optional', 'defaulted', 'finish']) {
        const header = new RegExp(`pub fn ${name}\\([\\s\\S]*?\\{\\n`);
        assert.match(instrumented, header);
        instrumented = instrumented.replace(header, '$&  panic as "core builder invoked"\n');
      }
      writeFileSync(coreFile, instrumented);
      writeFileSync(probe, prefix + `import gleam/io
pub fn main() {
let original = s.DefinitionError("first error")
let failed: Result(s.Record(fn(Int) -> fn(Option(String)) -> fn(Bool) -> Int, Nil), s.DefinitionError) = Error(original)
let result = failed
|> record.required("a", s.safe_integer())
|> record.optional("b", s.string())
|> record.defaulted("c", s.boolean(), s.json_null())
|> record.finish(s.Strict)
let assert Error(error) = result
let assert True = error == original
io.println("short circuit passed")
}
`);
      result = run('gleam', ['run', '--target', target], consumer);
      assert.equal(result.status, 0, result.output);
      assert.equal(result.stdout.trim(), 'short circuit passed');
      for (const body of [
        's.required(s.record(fn(x) { x }), "a", s.string())',
        's.optional(s.record(fn(x) { x }), "a", s.string())',
        's.defaulted(s.record(fn(x) { x }), "a", s.boolean(), s.json_bool(True))',
        's.finish(s.record(Nil), s.Strict)',
      ]) {
        writeFileSync(probe, prefix + `pub fn main() { ${body} }`);
        result = run('gleam', ['run', '--target', target], consumer);
        assert.notEqual(result.status, 0, `${target}: instrumentation did not execute`);
        assert.match(result.output, /core builder invoked/, result.output);
      }
    }
  } finally {
    rmSync(directory, {recursive: true, force: true});
  }
});
