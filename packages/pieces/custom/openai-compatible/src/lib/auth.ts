import { PieceAuth, Property } from '@activepieces/pieces-framework';
import { openaiCompatibleClient } from './common/client';

export const openaiCompatibleAuth = PieceAuth.CustomAuth({
  required: true,
  description: `Connect any OpenAI-compatible API with your own key (BYOK).

**Base URL examples**
- OpenAI: \`https://api.openai.com/v1\`
- OpenRouter: \`https://openrouter.ai/api/v1\`
- Groq: \`https://api.groq.com/openai/v1\`
- DeepSeek: \`https://api.deepseek.com/v1\`
- Ollama / LM Studio / vLLM on your server: \`http://<host>:<port>/v1\`

The key is stored encrypted in this Activepieces instance. Leave it empty for local servers that need no key.`,
  props: {
    baseUrl: Property.ShortText({
      displayName: 'Base URL',
      description: 'The API root, usually ending in /v1 (without /chat/completions).',
      required: true,
    }),
    apiKey: PieceAuth.SecretText({
      displayName: 'API Key',
      description: 'Sent as "Authorization: Bearer <key>". Optional for local servers.',
      required: false,
    }),
  },
  validate: async ({ auth }) => {
    try {
      const models = await openaiCompatibleClient.listModels({ baseUrl: auth.baseUrl, apiKey: auth.apiKey });
      if (models.length === 0) {
        return { valid: false, error: 'Connected, but the endpoint listed no models at /models.' };
      }
      return { valid: true };
    }
    catch (error) {
      return { valid: false, error: openaiCompatibleClient.describeError(error) };
    }
  },
});
