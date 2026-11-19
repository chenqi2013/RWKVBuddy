export function toolRequest(response) {
  const nested = response.tool && typeof response.tool === 'object' && !Array.isArray(response.tool);
  const name = nested ? response.tool.name : response.tool;
  let args = nested ? response.tool.arguments : response.arguments;
  if (typeof args === 'string') {
    try { args = JSON.parse(args); } catch {}
  }
  return {
    name: typeof name === 'string' && name.trim() ? name.trim() : 'tool.invalid',
    arguments: args,
  };
}
