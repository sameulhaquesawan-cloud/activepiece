function resolveReasoningEffort({ reasoningEffort, customReasoningEffort }: { reasoningEffort: string | undefined; customReasoningEffort: string | undefined }): string | undefined {
  const choice = reasoningEffort ?? DEFAULT_REASONING_EFFORT;
  if (choice === OMIT_REASONING) {
    return undefined;
  }
  if (choice === CUSTOM_REASONING) {
    const custom = customReasoningEffort?.trim();
    return custom ? custom : undefined;
  }
  return choice;
}

function build(input: ChatRequestInput): Record<string, unknown> {
  const messages = [
    ...(input.systemPrompt?.trim() ? [{ role: 'system', content: input.systemPrompt }] : []),
    { role: 'user', content: input.prompt },
  ];
  const reasoningEffort = resolveReasoningEffort({
    reasoningEffort: input.reasoningEffort,
    customReasoningEffort: input.customReasoningEffort,
  });
  const tokenLimitParameter = input.tokenLimitParameter ?? DEFAULT_TOKEN_LIMIT_PARAMETER;
  return {
    model: input.model,
    messages,
    ...(reasoningEffort ? { reasoning_effort: reasoningEffort } : {}),
    ...(typeof input.maxOutputTokens === 'number' && input.maxOutputTokens > 0 ? { [tokenLimitParameter]: input.maxOutputTokens } : {}),
    ...(typeof input.temperature === 'number' ? { temperature: input.temperature } : {}),
    ...(input.extraFields ?? {}),
  };
}

function toOutput(response: { model?: string; choices?: { finish_reason?: string; message?: { content?: string | null; reasoning_content?: string | null; reasoning?: string | null } }[]; usage?: Record<string, unknown> }) {
  const choice = response.choices?.[0];
  return {
    text: choice?.message?.content ?? '',
    reasoning: choice?.message?.reasoning_content ?? choice?.message?.reasoning ?? null,
    model: response.model ?? null,
    finishReason: choice?.finish_reason ?? null,
    usage: response.usage ?? null,
  };
}

export const chatRequest = { build, toOutput, resolveReasoningEffort };

export const DEFAULT_REASONING_EFFORT = 'high';
export const OMIT_REASONING = 'omit';
export const CUSTOM_REASONING = 'custom';
export const DEFAULT_TOKEN_LIMIT_PARAMETER = 'max_completion_tokens';

export type ChatRequestInput = {
  model: string;
  prompt: string;
  systemPrompt?: string;
  reasoningEffort?: string;
  customReasoningEffort?: string;
  maxOutputTokens?: number;
  tokenLimitParameter?: string;
  temperature?: number;
  extraFields?: Record<string, unknown>;
};
