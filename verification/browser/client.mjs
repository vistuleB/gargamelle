import {build,s,unwrap,Ok,toList} from '../generated-api.mjs';
import {evaluate,regexCases,nativeJSRegex} from './evaluate.mjs';
import * as docs from '../../build/dev/javascript/gargamelle/gargamelle/documentation.mjs';
const require=(value,message)=>{if(!value)throw new Error(message);};
const equal=(a,b,message)=>require(JSON.stringify(a)===JSON.stringify(b),message);
const status=document.getElementById('status'),output=document.getElementById('results');
const report={userAgent:navigator.userAgent,vendor:navigator.vendor,platform:navigator.platform,
  source:null,startedAt:new Date().toISOString(),typed:[],generated:[],regex:[],renderer:[]};
let checkpoint={stage:'loading'};
try{
  const fixture=await fetch('/fixture.json').then(r=>r.json());report.source=fixture.source;
  for(const module of fixture.typed){
    checkpoint={stage:'typed',module:module.path};
    const exports=await import(module.path);
    for(const name of module.tests){checkpoint={stage:'typed',module:module.path,name};exports[name]();report.typed.push(module.path+':'+name);}
  }
  for(const [index,row] of fixture.rows.entries()){
    checkpoint={stage:'generated',index};
    const definition=build(row.recipe),schema=s.schema_string(definition, s.JsonLayout$Compact$const),cases=[];
    equal(schema,row.schema,'Schema mismatch at '+index);
    for(const [inputIndex,input] of row.inputs.entries()){
      checkpoint={stage:'generated',index,inputIndex};
      const actual=evaluate(definition,input);equal(actual,row.expected[inputIndex],'Acceptance/output/diagnostic mismatch at '+index+':'+inputIndex);cases.push(actual);
    }
    equal(s.schema_string(definition, s.JsonLayout$Compact$const),schema,'Definition changed after decoding at '+index);
    report.generated.push({index,schema,cases});
    if(index%40===0){status.textContent=`Running generated definitions: ${index+1}/${fixture.rows.length}`;await new Promise(resolve=>requestAnimationFrame(resolve));}
  }
  for(const [index,entry] of regexCases.entries()){
    checkpoint={stage:'regex',index};
    const expected=nativeJSRegex(entry),definition=s.pattern(s.string(),entry.pattern),valid=definition instanceof Ok;
    require(valid===expected.valid,'Pattern syntax differs from browser RegExp at '+index);
    let actual={valid};
    if(valid){actual.matched=s.validate(definition[0],unwrap(s.parse(JSON.stringify(entry.text)))) instanceof Ok;
      require(actual.matched===expected.matched,'Pattern matching differs from browser RegExp at '+index);}
    report.regex.push(actual);
  }
  const rendererCheck=(name,condition)=>{require(condition,'Renderer: '+name);report.renderer.push(name);};
  checkpoint={stage:'renderer'};
  const tree=build({kind:'recursive'});
  const fragment=docs.render(s.description(tree,'<img src="invalid" onerror="window.injected=true">'),'browser-tree');
  const renderer=document.getElementById('renderer');renderer.innerHTML=fragment;
  rendererCheck('escaped descriptions',!renderer.querySelector('img,script')&&renderer.textContent.includes('<img'));
  rendererCheck('rendered article',renderer.querySelector('article')!==null);
  const nodes=()=>[...renderer.querySelectorAll('details.node')];
  rendererCheck('nested folding controls',nodes().length>1);
  const ids=[...renderer.querySelectorAll('[id]')].map(e=>e.id);
  rendererCheck('unique IDs',new Set(ids).size===ids.length);
  const links=[...renderer.querySelectorAll('a.reference')];
  rendererCheck('resolved recursive references',links.length>0&&links.every(a=>document.getElementById(decodeURIComponent(new URL(a.href).hash.slice(1)))));
  await import('/assets/reference.js');
  document.querySelector('[data-fold="expand"]').click();rendererCheck('expand all',nodes().every(e=>e.open));
  document.querySelector('[data-fold="collapse"]').click();rendererCheck('collapse all',nodes().every(e=>!e.open));
  const first=nodes()[0];first.querySelector('summary').click();rendererCheck('native disclosure toggle',first.open);
  const states=nodes().map(e=>e.open);
  dispatchEvent(new Event('beforeprint'));rendererCheck('beforeprint opens nodes',nodes().every(e=>e.open));
  dispatchEvent(new Event('afterprint'));rendererCheck('afterprint restores nodes',nodes().every((e,i)=>e.open===states[i]));
  document.querySelector('[data-fold="collapse"]').click();
  location.hash=new URL(links[0].href).hash;
  await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
  const target=document.getElementById(decodeURIComponent(location.hash.slice(1)));
  rendererCheck('hash navigation reveals definition',target&&target.querySelector('details')?.open);
  let calls=0;
  const mapped=s.map(s.string(),()=>{calls++;throw new Error('Documentation decoded example');});
  const examples=unwrap(docs.render_examples(mapped,'examples',toList([unwrap(s.parse('"</article><script>window.injected=true</script>"'))])));
  const container=document.createElement('div');container.innerHTML=examples;
  rendererCheck('checked examples suppress converters',calls===0);
  rendererCheck('checked examples escape markup',container.querySelectorAll('article').length===1&&!container.querySelector('script'));
  const record=build({kind:'record',fields:[
    {name:'name',child:{kind:'string'}},
    {name:'tags',child:{kind:'array',child:{kind:'string'}}},
    {name:'enabled',child:{kind:'boolean'}},
    {name:'metadata',child:{kind:'dictionary',child:{kind:'string'}}},
    {name:'settings',child:{kind:'record',fields:[
      {name:'label',child:{kind:'string'}},
      {name:'notifications',child:{kind:'boolean'}},
      {name:'theme',child:{kind:'string'}},
    ]}},
  ]});
  renderer.insertAdjacentHTML('afterbegin',docs.render(record,'record-alignment'));
  renderer.querySelector('details').open=true;
  const aligned=parent=>{
    const siblings=[...parent.children].filter(e=>e.classList.contains('node'));
    require(siblings.some(e=>e.tagName==='DETAILS')&&siblings.some(e=>e.classList.contains('leaf')),'Mixed folding fixture missing');
    const lefts=siblings.map(e=>e.querySelector('code').getBoundingClientRect().left);
    return Math.max(...lefts)-Math.min(...lefts)<0.5;
  };
  const recordChildren=renderer.querySelector('#record-alignment details > .node-body > .children');
  rendererCheck('record labels align with open children',aligned(recordChildren));
  [...recordChildren.children].filter(e=>e.tagName==='DETAILS').forEach(e=>{e.open=false;});
  rendererCheck('record labels align with closed children',aligned(recordChildren));
  const heights=[...recordChildren.children].map(e=>e.getBoundingClientRect().height);
  rendererCheck('record rows have uniform height including last',Math.max(...heights)-Math.min(...heights)<0.5);
  const nested=[...recordChildren.children].find(e=>e.querySelector('summary > code')?.textContent==='settings');nested.open=true;
  const nestedChildren=nested.querySelector('.children');
  rendererCheck('last nested row ends at next divider with guide inset',
    Math.abs(nestedChildren.lastElementChild.getBoundingClientRect().bottom-nested.getBoundingClientRect().bottom)<0.5
    && parseFloat(getComputedStyle(nestedChildren,'::before').bottom)===10);
  nested.open=true;
  const alternatives=target.querySelector('details > .node-body > .children');
  [...alternatives.children].filter(e=>e.tagName==='DETAILS').forEach(e=>{e.open=true;});
  rendererCheck('alternative labels align with open children',aligned(alternatives));
  [...alternatives.children].filter(e=>e.tagName==='DETAILS').forEach(e=>{e.open=false;});
  rendererCheck('alternative labels align with closed children',aligned(alternatives));
  report.status='passed';
}catch(error){report.status='failed';report.failure={checkpoint,message:String(error),stack:error.stack};}
report.finishedAt=new Date().toISOString();
const result=await fetch('/result?browser='+encodeURIComponent(new URL(location.href).searchParams.get('browser')??'browser'),{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(report)}).then(r=>r.json());
status.textContent=result.accepted?`PASS — ${report.typed.length} typed tests; ${report.generated.reduce((n,r)=>n+r.cases.length,0)} generated cases; ${report.regex.length} regex cases; ${report.renderer.length} renderer checks`:'FAIL — see retained report';
output.textContent=JSON.stringify({userAgent:report.userAgent,status:report.status,server:result,failure:report.failure},null,2);
