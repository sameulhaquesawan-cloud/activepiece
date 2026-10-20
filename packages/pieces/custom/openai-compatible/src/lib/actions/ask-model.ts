import { createAction, Property } from '@activepieces/pieces-framework';
import { openaiCompatibleAuth } from '../auth';
import { chatRequest } from '../common/chat-request';
import { openaiCompatibleClient } from '../common/client';
import { customReasoningEffortProp, modelDropdown, reasoningEffortDropdown, tokenLimitParameterDropdown } from '../common/props';

export const askModel = createAction({
  auth: openaiCompatibleAuth,
  name: 'ask_model',
  displayName: 'Ask Model',
  description: 'Send a prompt to any OpenAI-compatible chat model (your own key), with reasoning effort high by default.',
  classification: 'READ',
  props: {
    model: modelDropdown,
    prompt: Property.LongText({
      displayName: 'Prompt',
      required: true,
    }),
    systemPrompt: Property.LongText({
      displayName: 'System prompt',
      description: 'Optional instructions for the model.',
      required: false,
    }),
    reasoningEffort: reasoningEffortDropdown,
    customReasoningEffort: customReasoningEffortProp,
    maxOutputTokens: Property.Number({
      displayName: 'Max output tokens',
      description: 'Leave empty to let the model use its own maximum.',
      required: false,
    }),
    tokenLimitParameter: tokenLimitParameterDropdown,
    temperature: Property.Number({
      displayName: 'Temperature',
      description: 'Leave empty for the model default (many reasoning models only accept the default).',
      required: false,
    }),
    extraFields: Property.Json({
      displayName: 'Extra request fields (JSON)',
      description: 'Optional provider-specific fields merged into the request body, e.g. {"top_p": 0.9} or {"response_format": {"type": "json_object"}}.',
      required: false,
    }),
  },
  async run({ auth, propsValue }) {
    const body = chatRequest.build({
      model: propsValue.model,
      prompt: propsValue.prompt,
      systemPrompt: propsValue.systemPrompt,
      reasoningEffort: propsValue.reasoningEffort,
      customReasoningEffort: propsValue.customReasoningEffort,
      maxOutputTokens: propsValue.maxOutputTokens,
      tokenLimitParameter: propsValue.tokenLimitParameter,
      temperature: propsValue.temperature,
      extraFields: openaiCompatibleClient.isRecord(propsValue.extraFields) ? propsValue.extraFields : undefined,
    });
    try {
      const response = await openaiCompatibleClient.createChatCompletion({
        connection: { baseUrl: auth.props.baseUrl, apiKey: auth.props.apiKey },
        body,
      });
      return chatRequest.toOutput(response);
    }
    catch (error) {
      throw new Error(openaiCompatibleClient.describeError(error));
    }
  },
});
