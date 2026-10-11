// Explicitly bounded host Unicode drift, not a general regex exemption.
export function knownUnicodeDifference({pattern,text,node,browser}) {
  return (pattern === '\\p{L}' || pattern === '\\p{Assigned}')
    && text === '\u{11DB0}'
    && node.valid === true && node.matched === false
    && browser.valid === true && browser.matched === true;
}
