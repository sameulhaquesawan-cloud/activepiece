import { createCustomApiCallAction } from '@activepieces/pieces-common';
import { createPiece, PieceCategory } from '@activepieces/pieces-framework';
import { askModel } from './lib/actions/ask-model';
import { listModelsAction } from './lib/actions/list-models';
import { openaiCompatibleAuth } from './lib/auth';
import { openaiCompatibleClient } from './lib/common/client';

export const openaiCompatible = createPiece({
  displayName: 'OpenAI Compatible (BYOK)',
  description: 'Use any OpenAI-compatible AI endpoint with your own key: live model list, reasoning effort high by default.',
  auth: openaiCompatibleAuth,
  minimumSupportedRelease: '0.92.0',
  logoUrl: 'https://cdn.activepieces.com/pieces/openai.png',
  categories: [PieceCategory.ARTIFICIAL_INTELLIGENCE],
  authors: ['opskit'],
  actions: [
    askModel,
    listModelsAction,
    createCustomApiCallAction({
      auth: openaiCompatibleAuth,
      baseUrl: (auth) => openaiCompatibleClient.normalizeBaseUrl(auth?.props.baseUrl ?? ''),
      authMapping: async (auth) => (auth.props.apiKey ? { Authorization: `Bearer ${auth.props.apiKey}` } : {}),
    }),
  ],
  triggers: [],
});

export { openaiCompatibleAuth };
