import { describe, expect, it } from 'vitest';
import { chatRequest } from './chat-request';

describe('chatRequest.build', () => {
  it('sends reasoning_effort high by default', () => {
    const body = chatRequest.build({ model: 'gpt-5', prompt: 'hi' });

    expect(body).toEqual({
      model: 'gpt-5',
      messages: [{ role: 'user', content: 'hi' }],
      reasoning_effort: 'high',
    });
  });

  it('omits reasoning_effort when "Don\'t send" is chosen', () => {
    const body = chatRequest.build({ model: 'llama3', prompt: 'hi', reasoningEffort: 'omit' });

    expect(body).not.toHaveProperty('reasoning_effort');
  });

  it('uses a custom reasoning value and ignores an empty one', () => {
    expect(chatRequest.build({ model: 'm', prompt: 'p', reasoningEffort: 'custom', customReasoningEffort: ' xhigh ' })).toMatchObject({ reasoning_effort: 'xhigh' });
    expect(chatRequest.build({ model: 'm', prompt: 'p', reasoningEffort: 'custom', customReasoningEffort: '  ' })).not.toHaveProperty('reasoning_effort');
  });

  it('adds a system prompt, token limit and temperature only when set', () => {
    const body = chatRequest.build({
      model: 'm',
      prompt: 'p',
      systemPrompt: 'be brief',
      reasoningEffort: 'low',
      maxOutputTokens: 512,
      temperature: 0,
    });

    expect(body).toEqual({
      model: 'm',
      messages: [{ role: 'system', content: 'be brief' }, { role: 'user', content: 'p' }],
      reasoning_effort: 'low',
      max_completion_tokens: 512,
      temperature: 0,
    });
  });

  it('can use max_tokens for older servers and skips non-positive limits', () => {
    expect(chatRequest.build({ model: 'm', prompt: 'p', maxOutputTokens: 100, tokenLimitParameter: 'max_tokens' })).toMatchObject({ max_tokens: 100 });
    expect(chatRequest.build({ model: 'm', prompt: 'p', maxOutputTokens: 0 })).not.toHaveProperty('max_completion_tokens');
  });

  it('merges extra fields last so the user can override', () => {
    const body = chatRequest.build({ model: 'm', prompt: 'p', extraFields: { top_p: 0.9, reasoning_effort: 'medium' } });

    expect(body).toMatchObject({ top_p: 0.9, reasoning_effort: 'medium' });
  });
});

describe('chatRequest.toOutput', () => {
  it('returns text, reasoning, model, finish reason and usage', () => {
    const output = chatRequest.toOutput({
      model: 'deepseek-reasoner',
      choices: [{ finish_reason: 'stop', message: { content: '42', reasoning_content: 'thinking...' } }],
      usage: { total_tokens: 10 },
    });

    expect(output).toEqual({ text: '42', reasoning: 'thinking...', model: 'deepseek-reasoner', finishReason: 'stop', usage: { total_tokens: 10 } });
  });

  it('handles an empty response', () => {
    expect(chatRequest.toOutput({})).toEqual({ text: '', reasoning: null, model: null, finishReason: null, usage: null });
  });
});
