export const host = { id: 'host', name: '主持人', prompt: '汇总各专家的实际发言，回应用户问题，保留分歧、限制和下一步行动。' };

export function normalizeTeam(value) {
  if (value == null) return null;
  if (!value || typeof value !== 'object' || typeof value.name !== 'string' || !value.name.trim() || value.name.length > 40 ||
      !Array.isArray(value.members) || value.members.length < 1 || value.members.length > 6) throw new Error('团队需要名称和 1–6 位专家');
  const names = new Set([host.name]);
  const ids = new Set([host.id]);
  const members = value.members.map(member => {
    if (!member || !/^[a-zA-Z0-9_-]{1,48}$/.test(member.id) || ids.has(member.id) ||
        typeof member.name !== 'string' || !member.name.trim() || member.name.trim() === '全体' || member.name.length > 20 || /[\s@，。！？、:：;；]/u.test(member.name.trim()) || names.has(member.name.trim()) ||
        typeof member.prompt !== 'string' || !member.prompt.trim() || member.prompt.length > 1200) throw new Error('专家需要唯一的名称、标识和职责（名称不能含空格或 @）');
    ids.add(member.id);
    names.add(member.name.trim());
    return { id: member.id, name: member.name.trim(), prompt: member.prompt.trim() };
  });
  return { name: value.name.trim(), members };
}

export function teamSpeakers(team, question) {
  // Only a standalone @ token addresses members; email addresses remain question data.
  const addressed = [...question.matchAll(/(?:^|\s)@([^\s@，。！？、:：;；]+)/gu)].map(match => match[1]);
  const roster = [...team.members, host];
  for (const name of addressed) if (name !== '全体' && !roster.some(member => member.name === name)) throw new Error(`团队中没有“${name}”，请使用 @成员名 后加空格提问`);
  const selected = addressed.length && !addressed.includes('全体') ? roster.filter(member => addressed.includes(member.name)) : roster;
  return selected;
}
