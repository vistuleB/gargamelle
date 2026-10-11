// Test-only typed recipe compiler. Calls public constructors; never injects nodes.
export function quote(text) {
  return '"'+[...text].map(c=>c==='\\'?'\\\\':c==='"'?'\\"':c==='\n'?'\\n':c==='\r'?'\\r':c==='\t'?'\\t':c.codePointAt(0)<32?`\\u{${c.codePointAt(0).toString(16)}}`:c).join('')+'"';
}
const option=n=>n==null?'None':`Some(${n})`;
const float=n=>{const [mantissa,exponent]=String(n).split('e');return (mantissa.includes('.')?mantissa:mantissa+'.0')+(exponent==null?'':'e'+exponent);};
export function compileRecipes(rows) {
  const definitions=[],seen=new Map();
  const expect=expression=>`{ let assert Ok(value) = ${expression}\n value }`;
  const mapped=(expression,convert)=>`s.map(${expression}, ${convert})`;
  const bounds=(a,expression)=>a.min!=null||a.max!=null?expect(`s.bounds(${expression}, ${option(a.min)}, ${option(a.max)})`):expression;
  const auxiliary=(a,output='Nil')=>mapped(build(a),`fn(_) -> ${output} { panic as "auxiliary converter executed" }`);
  const record=fields=>{
    const payload='json.object(['+fields.map((f,i)=>`#(${quote(f.name)}, ${f.presence==='optional'?`presence(v${i})`:`v${i}`})`).join(',')+'])';
    const constructor=fields.reduceRight((body,_,i)=>`fn(v${i}) { ${body} }`,payload);
    let expression=`s.record(${constructor})`;
    for(const f of fields)expression=expect(`s.${f.presence==='optional'?'optional':f.presence==='defaulted'?'defaulted':'required'}(${expression}, ${quote(f.name)}, ${build(f.child)}${f.presence==='defaulted'?`, ${expect(`s.parse(${quote(JSON.stringify(f.default))})`)}`:''})`);
    return expression;
  };
  function build(a) {
    const key=JSON.stringify(a);if(seen.has(key))return seen.get(key)+'()';
    let expression;
    switch(a.kind) {
      case 'boolean':expression=mapped('s.boolean()','json.bool');break;
      case 'null':expression=mapped('s.null()','fn(_) { json.null() }');break;
      case 'string':{
        let d=bounds(a,'s.text()');for(const p of a.patterns??[])d=expect(`s.pattern(${d}, ${quote(p)})`);
        expression=mapped(d,'json.string');break;
      }
      case 'integer':expression=mapped(bounds(a,'s.safe_integer()'),'json.int');break;
      case 'number':{
        const bound=(n,exclusive)=>n==null?'None':`Some(s.${exclusive?'Exclusive':'Inclusive'}(${float(n)}))`;
        const d=a.min!=null||a.max!=null?expect(`s.number_bounds(s.number(), ${bound(a.min,a.exclusiveMin)}, ${bound(a.max,a.exclusiveMax)})`):'s.number()';
        expression=mapped(d,'json.float');break;
      }
      case 'enum':expression=mapped(expect(`s.string_enum([${a.values.map(quote).join(',')}])`),'json.string');break;
      case 'constant':{
        const d=a.value===null?'s.null_constant()':typeof a.value==='string'?`s.string_constant(${quote(a.value)})`:typeof a.value==='boolean'?`s.boolean_constant(${a.value?'True':'False'})`:expect(`s.integer_constant(${a.value})`);
        expression=mapped(d,a.value===null?'fn(_) { json.null() }':typeof a.value==='string'?'json.string':typeof a.value==='boolean'?'json.bool':'json.int');break;
      }
      case 'recursive':expression=expect(`s.recursive("generated-tree", fn(self) {
        s.any_of([s.lift(s.map(s.number(), fn(x) { json.object([#("leaf", json.float(x))]) })),
          s.map(s.array(self), fn(xs) { json.object([#("children", json.array(xs, fn(x) { x }))]) })])
      })`);break;
      case 'array':expression=mapped(bounds(a,`s.array(${build(a.child)})`),'fn(xs) { json.array(xs, fn(x) { x }) }');break;
      case 'dictionary':expression=mapped(bounds(a,`s.dictionary(${build(a.child)})`),'json.object');break;
      case 'property_names':expression=mapped(expect(`s.property_names(s.dictionary(${build(a.child)}), ${auxiliary(a.keys,'String')})`),'json.object');break;
      case 'contains':expression=mapped(expect(`s.contains(s.array(${build(a.child)}), ${auxiliary(a.matching)}, ${a.minimum}, ${option(a.maximum)})`),'fn(xs) { json.array(xs, fn(x) { x }) }');break;
      case 'record':expression=`s.finish(${record(a.fields)}, s.${a.open?'Open':'Strict'})`;break;
      case 'tuple':{
        const constructor=a.children.reduceRight((body,_,i)=>`fn(v${i}) { ${body} }`,`json.array([${a.children.map((_,i)=>'v'+i).join(',')}], fn(x) { x })`);
        let tuple=`s.tuple(${constructor})`;for(const c of a.children)tuple=`s.element(${tuple}, ${build(c)})`;
        expression=`s.finish_tuple(${tuple})`;break;
      }
      case 'nullable':expression=mapped(`s.nullable(${build(a.child)})`,'presence');break;
      case 'any':case 'one':expression=expect(`s.${a.kind}_of([${a.children.map(build).join(',')}])`);break;
      case 'exclude':expression=`s.exclude(${build(a.child)}, ${auxiliary(a.forbidden)})`;break;
      case 'conditional':expression=`s.if_then${a.alternative?'_else':''}(${build(a.child)}, ${auxiliary(a.condition)}, ${auxiliary(a.consequence)}${a.alternative?', '+auxiliary(a.alternative):''})`;break;
      case 'map':expression=mapped(build(a.child),'fn(x) { json.object([#("mapped", x)]) }');break;
      case 'description':case 'title':expression=`s.${a.kind}(${build(a.child)}, ${quote(a.value??a.kind)})`;break;
      case 'tagged':expression=expect(`s.tagged(${quote(a.tag)}, [${a.branches.map(b=>{
        let v=`s.variant(${quote(b.tag)}, ${record(b.fields)}, s.${b.open?'Open':'Strict'})`;
        if(b.description!=null)v=`s.variant_description(${v}, ${quote(b.description)})`;
        return `s.variant_map(${v}, fn(payload) { json.object([#("tag", json.string(${quote(b.tag)})), #("payload", payload)]) })`;
      }).join(',')}])`);break;
      default:throw new Error('Unsupported typed recipe '+a.kind);
    }
    const name='definition_'+definitions.length;
    definitions.push(`fn ${name}() -> s.Definition(json.Json) { ${expression} }`);seen.set(key,name);
    return name+'()';
  }
  const fixtures=rows.map((row,i)=>`#(${i}, fn() { ${build(row.recipe)} }, [${row.inputs.map(quote).join(',')}])`);
  return `import gargamelle as s\nimport gleam/json\nimport gleam/option.{None, Some}\n
fn presence(value) { case value { Some(x) -> json.object([#("some", x)]) None -> json.object([#("none", json.bool(True))]) } }
${definitions.join('\n')}
pub fn fixtures() { [${fixtures.join(',\n')}] }\n`;
}
