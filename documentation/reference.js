const nodes=()=>[...document.querySelectorAll('details.node')];
 document.querySelectorAll('[data-fold]').forEach(button=>button.addEventListener('click',()=>nodes().forEach(node=>{node.open=button.dataset.fold==='expand';})));
 const revealTarget=()=>{let id;try{id=decodeURIComponent(location.hash.slice(1));}catch{return;}const target=document.getElementById(id);if(!target)return;for(let parent=target;parent;parent=parent.parentElement)if(parent.tagName==='DETAILS')parent.open=true;const child=target.querySelector('details');if(child)child.open=true;};
 addEventListener('hashchange',revealTarget);revealTarget();
 let foldedBeforePrint;
 addEventListener('beforeprint',()=>{if(foldedBeforePrint)return;foldedBeforePrint=nodes().filter(node=>!node.open);foldedBeforePrint.forEach(node=>{node.open=true;});});
 addEventListener('afterprint',()=>{foldedBeforePrint?.forEach(node=>{node.open=false;});foldedBeforePrint=undefined;});
