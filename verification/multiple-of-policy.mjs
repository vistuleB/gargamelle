// Investigation only: print independent-validator disagreements for review.
import Ajv2020 from 'ajv/dist/2020.js';
import {compileSupplementary} from './supplementary-oracle.mjs';
const ajv=new Ajv2020({strict:false});
for(const divisor of [0.1,0.01,0.25,3,9007199254740991]){
  const schema={$schema:'https://json-schema.org/draft/2020-12/schema',type:'number',multipleOf:divisor};
  const first=ajv.compile(schema),second=await compileSupplementary(schema);
  for(const value of [0,0.3,0.7,0.29,1,3,9007199254740991,1e308]){
    const a=first(value),b=second(value).accepted;
    if(a!==b)console.log(JSON.stringify({divisor,value,ajv:a,hyperjump:b}));
  }
}
