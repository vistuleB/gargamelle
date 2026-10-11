# Renderer assets

Copy these files beside your HTML page. See the [renderer recipe](advanced.html)
for the complete page and controls. Both assets are distributed under the
[MIT License](license.html).

## reference.css

```css
:root{font-family:system-ui,sans-serif;color:#24313a;background:#eef1f3;line-height:1.55}body{max-width:1080px;margin:40px auto;padding:0 28px}header,article,.notice{background:white;border:1px solid #d7dfe3;border-radius:8px;padding:24px 30px;margin:20px 0}h1{font-size:34px;margin:0}h2{font-size:30px;margin:50px 0 0}h3{font-size:23px;margin:0 0 12px}h4{font-size:15px;margin:26px 0 8px;overflow-wrap:anywhere;color:#38596a}p{margin:10px 0}nav{display:flex;gap:18px;flex-wrap:wrap;margin-top:20px}a{color:#175d83}code{font:14px ui-monospace,monospace;overflow-wrap:anywhere}.badge{font-size:10px;text-transform:uppercase;color:#596b75;margin-left:6px}small{display:block;font-size:12px;color:#586d79;margin-top:6px;overflow-wrap:anywhere}.type{font:12px ui-monospace,monospace;color:#586d79;margin-left:10px;overflow-wrap:anywhere}.badge.policy{color:#925018;background:#fff3e5;border:1px solid #ecd4b7;border-radius:999px;padding:2px 6px;white-space:nowrap}.node{border-top:1px solid #e1e7ea;padding:10px 0}.node[open]{padding-bottom:0}.node summary{cursor:pointer;position:relative;display:block;list-style:none;padding:3px 0 3px 18px;overflow-wrap:anywhere}.node summary::-webkit-details-marker{display:none}.node summary::before{content:"";display:inline-block;width:10px;height:8px;margin-left:-18px;margin-right:8px;font:14px ui-monospace,monospace;vertical-align:calc(.666667ex - 4px);background:#58798a;clip-path:polygon(0 0,100% 50%,0 100%)}.node[open]>summary::before{clip-path:polygon(0 0,100% 0,50% 100%)}.node summary:hover{color:#175d83}.node summary:focus-visible,button:focus-visible,a:focus-visible{outline:2px solid #175d83;outline-offset:3px}.node-body{padding-left:18px}.children{position:relative;border-left:2px solid transparent;padding-left:20px;margin:12px 0 0 2px}.children::before{content:"";position:absolute;left:-2px;top:0;bottom:10px;width:2px;background:#e1e7ea}.meaning{font-size:14px;margin:5px 0}.constraint,.source{font-size:12px;color:#586d79}.leaf{padding-left:18px}.leaf>div:first-child{padding:3px 0}.reference{font-size:12px}.shared:target{outline:2px solid #8cb2c7;outline-offset:8px}.controls{display:flex;gap:10px;margin:20px 0}button{font:inherit;font-size:13px;border:1px solid #aabec9;border-radius:5px;padding:7px 12px;background:white;color:#175d83;cursor:pointer}.lead{font-size:15px}.notice{font-size:14px}footer{margin:40px 0;font-size:13px;color:#586d79}@media(max-width:650px){body{padding:0 12px}header,article{padding:16px}.children{padding-left:12px}.node-body{padding-left:10px}.type{display:block;margin:4px 0}}@media print{@page{size:A4;margin:16mm}body{max-width:none;margin:0;padding:0;background:white;font-size:10pt}header,article,.notice{border:0;padding:0;border-radius:0}nav,.controls{display:none}.node{break-inside:auto}.node summary{break-after:avoid}.node-body{display:block!important}details::details-content{display:block!important;content-visibility:visible!important}.leaf{break-inside:avoid}.provider{break-before:page}h2,h3,h4{break-after:avoid}tr{break-inside:avoid}thead{display:table-header-group}td{font-size:9pt}small,.constraint{font-size:8pt}h1{font-size:24pt}h2{font-size:20pt}h3{font-size:16pt}}
```

## reference.js

```javascript
const nodes=()=>[...document.querySelectorAll('details.node')];
 document.querySelectorAll('[data-fold]').forEach(button=>button.addEventListener('click',()=>nodes().forEach(node=>{node.open=button.dataset.fold==='expand';})));
 const revealTarget=()=>{let id;try{id=decodeURIComponent(location.hash.slice(1));}catch{return;}const target=document.getElementById(id);if(!target)return;for(let parent=target;parent;parent=parent.parentElement)if(parent.tagName==='DETAILS')parent.open=true;const child=target.querySelector('details');if(child)child.open=true;};
 addEventListener('hashchange',revealTarget);revealTarget();
 let foldedBeforePrint;
 addEventListener('beforeprint',()=>{if(foldedBeforePrint)return;foldedBeforePrint=nodes().filter(node=>!node.open);foldedBeforePrint.forEach(node=>{node.open=true;});});
 addEventListener('afterprint',()=>{foldedBeforePrint?.forEach(node=>{node.open=false;});foldedBeforePrint=undefined;});
```
