import { AuthenticationType, httpClient, HttpError, HttpMethod, HttpRequest } from '@activepieces/pieces-common';

function normalizeBaseUrl(baseUrl: string): string {
  return baseUrl
    .trim()
    .replace(/\/+$/, '')
    .replace(/\/(chat\/completions|models)$/, '');
}

function authFor(apiKey: string | undefined): Pick<HttpRequest, 'authentication'> {
  const token = apiKey?.trim();
  if (!token) {
    return {};
  }
  return { authentication: { type: AuthenticationType.BEARER_TOKEN, token } };
}

async function listModels({ baseUrl, apiKey }: ConnectionSettings): Promise<ModelInfo[]> {
  const response = await httpClient.sendRequest<ModelsResponse>({
    method: HttpMethod.GET,
    url: `${normalizeBaseUrl(baseUrl)}/models`,
    timeout: MODELS_TIMEOUT_MS,
    ...authFor(apiKey),
  });
  const items = Array.isArray(response.body?.data) ? response.body.data : [];
  return items
    .filter((item): item is RawModel => typeof item?.id === 'string' && item.id.length > 0)
    .map((item) => ({ id: item.id, ownedBy: item.owned_by }))
    .sort((a, b) => a.id.localeCompare(b.id));
}

async function createChatCompletion({ connection, body }: { connection: ConnectionSettings; body: Record<string, unknown> }): Promise<ChatCompletionResponse> {
  const response = await httpClient.sendRequest<ChatCompletionResponse>({
    method: HttpMethod.POST,
    url: `${normalizeBaseUrl(connection.baseUrl)}/chat/completions`,
    body,
    timeout: CHAT_TIMEOUT_MS,
    ...authFor(connection.apiKey),
  });
  return response.body;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function providerMessage(body: unknown): string | undefined {
  if (typeof body === 'string') {
    return body;
  }
  if (!isRecord(body)) {
    return undefined;
  }
  const error = body['error'];
  if (typeof error === 'string') {
    return error;
  }
  if (isRecord(error) && typeof error['message'] === 'string') {
    return error['message'];
  }
  return undefined;
}

function describeError(error: unknown): string {
  if (!(error instanceof HttpError)) {
    return error instanceof Error ? error.message : String(error);
  }
  const { status, body } = error.response;
  const detail = providerMessage(body)?.slice(0, MAX_ERROR_DETAIL);
  const hint = STATUS_HINTS[status] ?? `The endpoint answered HTTP ${status}.`;
  return detail ? `${hint} Provider said: ${detail}` : hint;
}

export const openaiCompatibleClient = { normalizeBaseUrl, listModels, createChatCompletion, describeError, isRecord };

const MODELS_TIMEOUT_MS = 15000;
const CHAT_TIMEOUT_MS = 600000;
const MAX_ERROR_DETAIL = 300;
const STATUS_HINTS: Record<number, string> = {
  400: 'The endpoint rejected the request (if it mentions reasoning_effort or a token limit, change "Reasoning effort" to "Don\'t send" or switch the token limit parameter).',
  401: 'The API key was rejected. Check the key in the connection.',
  403: 'The API key is not allowed to use this model or endpoint.',
  404: 'Not found: check the Base URL (it usually ends in /v1) and the model name.',
  429: 'Rate limit or quota reached at the provider. Try again later or check your billing.',
};

export type ConnectionSettings = {
  baseUrl: string;
  apiKey?: string;
};

export type ModelInfo = {
  id: string;
  ownedBy?: string;
};

type RawModel = {
  id: string;
  owned_by?: string;
};

type ModelsResponse = {
  data?: RawModel[];
};

export type ChatCompletionResponse = {
  id?: string;
  model?: string;
  choices?: {
    finish_reason?: string;
    message?: {
      content?: string | null;
      reasoning_content?: string | null;
      reasoning?: string | null;
    };
  }[];
  usage?: Record<string, unknown>;
};
