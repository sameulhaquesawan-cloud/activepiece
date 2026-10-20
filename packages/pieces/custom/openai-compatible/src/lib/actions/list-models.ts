import { createAction } from '@activepieces/pieces-framework';
import { openaiCompatibleAuth } from '../auth';
import { openaiCompatibleClient } from '../common/client';

export const listModelsAction = createAction({
  auth: openaiCompatibleAuth,
  name: 'list_models',
  displayName: 'List Models',
  description: 'Return the models the endpoint currently offers (from /models).',
  classification: 'READ',
  props: {},
  async run({ auth }) {
    try {
      const models = await openaiCompatibleClient.listModels({ baseUrl: auth.props.baseUrl, apiKey: auth.props.apiKey });
      return { count: models.length, models };
    }
    catch (error) {
      throw new Error(openaiCompatibleClient.describeError(error));
    }
  },
});
