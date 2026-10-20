import { Property } from '@activepieces/pieces-framework';
import { openaiCompatibleAuth } from '../auth';
import { openaiCompatibleClient } from './client';
import { CUSTOM_REASONING, DEFAULT_REASONING_EFFORT, DEFAULT_TOKEN_LIMIT_PARAMETER, OMIT_REASONING } from './chat-request';

async function loadModelOptions({ auth }: { auth: unknown }) {
  const connection = connectionFrom(auth);
  if (!connection) {
    return { disabled: true, placeholder: 'Choose a connection first', options: [] };
  }
  try {
    const models = await openaiCompatibleClient.listModels(connection);
    return {
      disabled: false,
      placeholder: models.length === 0 ? 'The endpoint listed no models' : 'Select a model',
      options: models.map((model) => ({ label: model.ownedBy ? `${model.id} (${model.ownedBy})` : model.id, value: model.id })),
    };
  }
  catch (error) {
    return { disabled: true, placeholder: `Could not load models: ${openaiCompatibleClient.describeError(error)}`, options: [] };
  }
}

function connectionFrom(auth: unknown): { baseUrl: string; apiKey?: string } | undefined {
  if (!openaiCompatibleClient.isRecord(auth) || !openaiCompatibleClient.isRecord(auth['props'])) {
    return undefined;
  }
  const { baseUrl, apiKey } = auth['props'];
  if (typeof baseUrl !== 'string' || baseUrl.trim() === '') {
    return undefined;
  }
  return { baseUrl, apiKey: typeof apiKey === 'string' ? apiKey : undefined };
}

export const modelDropdown = Property.Dropdown({
  auth: openaiCompatibleAuth,
  displayName: 'Model',
  description: 'Loaded live from the endpoint\'s /models list. Use refresh to reload.',
  required: true,
  refreshers: [],
  refreshOnSearch: false,
  options: async ({ auth }) => loadModelOptions({ auth }),
});

export const reasoningEffortDropdown = Property.StaticDropdown({
  displayName: 'Reasoning effort',
  description: 'Sent as reasoning_effort. High is the highest level most reasoning models accept. Choose "Don\'t send" for endpoints/models that reject the field.',
  required: false,
  defaultValue: DEFAULT_REASONING_EFFORT,
  options: {
    disabled: false,
    options: [
      { label: 'High (default)', value: 'high' },
      { label: 'Extra high (xhigh — only some models)', value: 'xhigh' },
      { label: 'Medium', value: 'medium' },
      { label: 'Low', value: 'low' },
      { label: 'Minimal', value: 'minimal' },
      { label: 'None (reasoning off — only some models)', value: 'none' },
      { label: 'Don\'t send', value: OMIT_REASONING },
      { label: 'Custom value', value: CUSTOM_REASONING },
    ],
  },
});

export const customReasoningEffortProp = Property.ShortText({
  displayName: 'Custom reasoning effort',
  description: 'Only used when "Reasoning effort" is "Custom value".',
  required: false,
});

export const tokenLimitParameterDropdown = Property.StaticDropdown({
  displayName: 'Token limit parameter',
  description: 'OpenAI reasoning models need max_completion_tokens; some older servers only accept max_tokens.',
  required: false,
  defaultValue: DEFAULT_TOKEN_LIMIT_PARAMETER,
  options: {
    disabled: false,
    options: [
      { label: 'max_completion_tokens (default)', value: 'max_completion_tokens' },
      { label: 'max_tokens', value: 'max_tokens' },
    ],
  },
});

export const modelOptions = { loadModelOptions, connectionFrom };
