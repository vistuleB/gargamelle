import {s,unwrap,Ok,Some} from '../generated-api.mjs';

const errorJSON=e=>({category:e.category,path:e.path,missing_key:e.missing_key instanceof Some?e.missing_key[0]:null,
  branches:[...e.branches].map(([index,errors])=>({index,errors:[...errors].map(errorJSON)})),matches:[...e.matches]});
export function evaluate(definition,input){
  const value=unwrap(s.parse(input)),before=s.to_string(value, s.JsonLayout$Compact$const),result=s.decode(definition,value);
  if(s.to_string(value, s.JsonLayout$Compact$const)!==before)throw new Error('Decoded input changed');
  const accepted=result instanceof Ok;
  if((s.validate(definition,value) instanceof Ok)!==accepted)throw new Error('Validate/decode disagreement');
  return {input,accepted,decoded:accepted?JSON.parse(JSON.stringify(result[0])):null,errors:accepted?[]:[...result[0]].map(errorJSON)};
}
export const patterns=['','.', '^.$','\\s','\\w','\\p{L}', '\\p{Assigned}','\\p{Script=Greek}',
  '\\p{Script_Extensions=Hiragana}','(?<x>a)|(?<x>b)','(?:(?<x>a)|(?<x>b))\\k<x>',
  '(?<=a)b','(?<!a)b','(a)?\\1','(?s:.)','(?i:a)','(?m:^a$)','^💜$',
  '\\p{IDS_Unary_Operator}','\\p{IDSU}','\\p{Modifier_Combining_Mark}','\\p{MCM}',
  '\\P{IDS_Unary_Operator}','\\P{IDSU}','\\P{Modifier_Combining_Mark}','\\P{MCM}',
  '[','\\a','\\p{letter}','a{2,1}','(?<x>a)(?<x>b)','[a-\\d]','\\uD800'];
export const texts=['','a','b','aa','bb','ab','A','a\n','\n','\u2028','\ufeff','\u0085','é','α','あ','💜',
  String.fromCodePoint(0x105c0),String.fromCodePoint(0x11db0)];
export const regexCases=patterns.flatMap(pattern=>texts.map(text=>({pattern,text})));
export function nativeJSRegex({pattern,text}){
  try{return {valid:true,matched:new RegExp(pattern,'u').test(text)};}
  catch(error){if(!(error instanceof SyntaxError))throw error;return {valid:false};}
}
