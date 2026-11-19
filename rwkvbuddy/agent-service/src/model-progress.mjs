// Read only public response fields from an incomplete JSON stream. Never expose
// reasoning fields, JSON syntax, file contents, or strings that merely mention keys.
export function modelProgress(text) {
  const source = String(text || '').trimStart().replace(/^```(?:json)?\s*/, '');
  let offset = 0;
  const space = () => { while (/\s/.test(source[offset] || '') && offset < source.length) offset++; };
  const string = () => {
    offset++;
    let value = '';
    while (offset < source.length) {
      const char = source[offset++];
      if (char === '"') return { value, complete: true };
      if (char !== '\\') { value += char; continue; }
      if (offset >= source.length) break;
      const escaped = source[offset++];
      if (escaped === 'u') {
        const hex = source.slice(offset, offset + 4);
        if (!/^[\da-f]{4}$/i.test(hex)) break;
        value += String.fromCharCode(parseInt(hex, 16)); offset += 4;
      } else {
        const escapes = { '"': '"', '\\': '\\', '/': '/', n: '\n', r: '\r', t: '\t', b: '\b', f: '\f' };
        if (!(escaped in escapes)) break;
        value += escapes[escaped];
      }
    }
    return { value, complete: false };
  };
  const read = (depth = 0) => {
    space();
    if (depth > 16 || offset >= source.length) return undefined;
    if (source[offset] === '"') return string().value;
    const open = source[offset];
    if (open === '{' || open === '[') {
      offset++;
      const value = open === '{' ? Object.create(null) : [];
      const close = open === '{' ? '}' : ']';
      while (offset < source.length) {
        space();
        if (source[offset] === close) { offset++; break; }
        let key;
        if (open === '{') {
          if (source[offset] !== '"') break;
          const token = string();
          if (!token.complete) break;
          key = token.value;
          space(); if (source[offset++] !== ':') break;
        }
        const start = offset;
        const item = read(depth + 1);
        if (item !== undefined) {
          if (open === '{') value[key] = item; else value.push(item);
        }
        if (offset === start) break;
        space();
        if (source[offset] !== ',') { if (source[offset] === close) offset++; break; }
        offset++;
      }
      return value;
    }
    const token = source.slice(offset).match(/^(?:true|false|null|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)/)?.[0];
    if (token) { offset += token.length; return null; }
    return undefined;
  };
  if (!source.startsWith('{')) return { progress: '', answerPreview: '', pendingTool: '' };
  const parsed = read();
  const result = parsed?.name === 'submit' ? parsed.arguments?.answer : parsed;
  const tool = typeof result?.tool === 'string' ? result.tool : result?.tool?.name;
  return {
    progress: typeof result?.progress === 'string' ? result.progress.slice(0, 600) : '',
    answerPreview: typeof result?.answer === 'string' ? result.answer.slice(0, 12000) : '',
    pendingTool: typeof tool === 'string' ? tool.slice(0, 80) : '',
  };
}
