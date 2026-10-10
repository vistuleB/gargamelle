import { mkdirSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
export function retainOperationalFailure({recipe,value,context,error},directory=fileURLToPath(new URL('./generated-failures/',import.meta.url))){
 mkdirSync(directory,{recursive:true});
 const file=join(directory,`${context.seed}-${context.index}-operational.json`);
 writeFileSync(file,JSON.stringify({contractRevision:5,classification:'operational-failure',context,recipe,value,error:{name:error.name,message:error.message,stack:error.stack}},null,2)+'\n');
 return file;
}

export function checkpointCase(recipe,values,context){
 const directory=fileURLToPath(new URL('./generated-failures/',import.meta.url));mkdirSync(directory,{recursive:true});
 const file=join(directory,'in-flight.json');
 writeFileSync(file,JSON.stringify({classification:'in-flight',context,recipe,values},null,2)+'\n');return file;
}
export function clearCheckpoint(file){unlinkSync(file);}
