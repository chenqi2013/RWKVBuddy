export function calculate(expression) {
  if (typeof expression !== 'string' || expression.length > 500) throw new Error('表达式过长');
  const tokens = expression.match(/\d+(?:\.\d+)?|[()+*/%-]/g) || [];
  if (tokens.join('') !== expression.replace(/\s/g, '') || tokens.length > 100) throw new Error('仅支持数字、括号和 + - * / %');
  let position = 0;
  const atom = () => {
    const token = tokens[position++];
    if (token === '+' || token === '-') return (token === '-' ? -1 : 1) * atom();
    if (token === '(') { const result = sum(); if (tokens[position++] !== ')') throw new Error('括号不匹配'); return result; }
    if (!token || !/^\d/.test(token)) throw new Error('表达式无效');
    return Number(token);
  };
  const product = () => {
    let result = atom();
    while (['*', '/', '%'].includes(tokens[position])) {
      const operator = tokens[position++]; const value = atom();
      result = operator === '*' ? result * value : operator === '/' ? result / value : result % value;
    }
    return result;
  };
  const sum = () => {
    let result = product();
    while (['+', '-'].includes(tokens[position])) { const operator = tokens[position++]; const value = product(); result = operator === '+' ? result + value : result - value; }
    return result;
  };
  const result = sum();
  if (position !== tokens.length || !Number.isFinite(result)) throw new Error('表达式无效或计算结果溢出');
  return { expression, result, note: '普通浮点计算，不替代财务整数核算。' };
}
export function analysisTool(name, args, snapshot, evidence) {
  if (!args || typeof args !== 'object' || Array.isArray(args)) throw new Error('工具参数须为对象');
  if (name === 'calculator') return calculate(args.expression);
  if (name === 'read_file') {
    const source = evidence.find((item) => item.id === args.evidenceId);
    if (!source || !snapshot.files[source.path]) throw new Error('证据 ID 不存在');
    const start = Math.max(1, Math.floor(Number(args.startLine) || 1));
    const count = Math.max(1, Math.min(100, Math.floor(Number(args.lineCount) || 60)));
    const lines = snapshot.files[source.path].content.split(/\r?\n/);
    return { evidenceId: source.id, path: source.path, startLine: start,
      endLine: Math.min(lines.length, start + count - 1), totalLines: lines.length,
      text: lines.slice(start - 1, start - 1 + count).join('\n').slice(0, 12000) };
  }
  if (name === 'search_text') {
    if (typeof args.query !== 'string' || !args.query.trim() || args.query.length > 200) throw new Error('搜索词须为 1–200 个字符');
    const matches = [];
    for (const source of evidence) {
      const content = snapshot.files[source.path]?.content;
      if (!content) continue;
      for (const [index, line] of content.split(/\r?\n/).entries()) {
        if (line.toLowerCase().includes(args.query.toLowerCase())) matches.push({ evidenceId: source.id, path: source.path, line: index + 1, text: line.slice(0, 500) });
        if (matches.length >= 24) return { matches, limited: true };
      }
    }
    return { matches, limited: false };
  }
  throw new Error('工具不可用：仅支持资料内读取、文字检索和计算，不提供联网搜索或命令执行');
}
