// Use server token counts when available. Other streams expose an explicitly
// estimated count until their final usage arrives; SSE chunks are not tokens.
export class GenerationMetrics {
  constructor(now = () => performance.now()) {
    this.now = now;
    this.started = null;
    this.initialTokens = 0;
    this.estimated = 0;
    this.counted = 0;
    this.source = 'estimated';
    this.tokens = 0;
  }
  update(chunk) {
    let exact = 0;
    let estimated = 0;
    for (const choice of chunk.choices || []) {
      const logs = choice.logprobs?.content;
      const ids = choice.token_ids || choice.delta?.token_ids;
      if (Array.isArray(logs) && logs.length) exact += logs.length;
      else if (Array.isArray(ids) && ids.length) exact += ids.length;
      const piece = choice.delta?.content || choice.message?.content || choice.text || '';
      const reasoning = choice.delta?.reasoning_content || '';
      // A fallback only: tokenizers differ by model and language.
      estimated += Buffer.byteLength(piece + reasoning, 'utf8') / 3;
    }
    this.estimated += estimated;
    this.counted += exact;
    const usage = chunk.usage?.completion_tokens;
    if (Number.isSafeInteger(usage) && usage >= 0) {
      this.tokens = usage;
      this.source = 'usage';
    } else if (exact > 0) {
      this.tokens = this.counted;
      this.source = 'tokens';
    } else if (this.source === 'estimated') this.tokens = Math.ceil(this.estimated);
    const time = this.now();
    if (this.started === null && this.tokens > 0) {
      this.started = time;
      this.initialTokens = this.tokens;
    }
    const elapsedMs = this.started === null ? 0 : time - this.started;
    // With only final usage, the first received text is an estimate rather than
    // a measured token count; use one token as the start of generation.
    const baseline = this.source === 'usage' ? Math.min(1, this.initialTokens) : this.initialTokens;
    return { completionTokens: this.tokens, source: this.source, elapsedMs: Math.round(elapsedMs),
      tokensPerSecond: elapsedMs >= 100 && this.tokens > baseline
        ? Math.round((this.tokens - baseline) * 10000 / elapsedMs) / 10 : null };
  }
}
