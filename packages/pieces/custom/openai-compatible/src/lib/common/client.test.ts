import { beforeEach, describe, expect, it, vi } from 'vitest';

const { sendRequest } = vi.hoisted(() => ({ sendRequest: vi.fn() }));

vi.mock('@activepieces/pieces-common', async (importOriginal) => {
  const original = await importOriginal<typeof import('@activepieces/pieces-common')>();
  return { ...original, httpClient: { sendRequest } };
});

import { HttpError } from '@activepieces/pieces-common';
import { openaiCompatibleAuth } from '../auth';
import { openaiCompatibleClient } from './client';
import { modelOptions } from './props';

describe('openaiCompatibleClient.normalizeBaseUrl', () => {
  it.each([
    ['https://api.openai.com/v1', 'https://api.openai.com/v1'],
    ['https://api.openai.com/v1/', 'https://api.openai.com/v1'],
    [' https://openrouter.ai/api/v1/chat/completions ', 'https://openrouter.ai/api/v1'],
    ['http://ollama:11434/v1/models', 'http://ollama:11434/v1'],
  ])('%s -> %s', (input, expected) => {
    expect(openaiCompatibleClient.normalizeBaseUrl(input)).toBe(expected);
  });
});

describe('openaiCompatibleClient.listModels', () => {
  beforeEach(() => {
    sendRequest.mockReset();
  });

  it('calls /models with a bearer token and returns sorted ids', async () => {
    sendRequest.mockResolvedValue({ body: { data: [{ id: 'o3', owned_by: 'openai' }, { id: 'gpt-4.1' }, { name: 'no-id' }] } });

    const models = await openaiCompatibleClient.listModels({ baseUrl: 'https://api.openai.com/v1/', apiKey: 'sk-test' });

    expect(models).toEqual([{ id: 'gpt-4.1', ownedBy: undefined }, { id: 'o3', ownedBy: 'openai' }]);
    expect(sendRequest).toHaveBeenCalledWith(expect.objectContaining({
      method: 'GET',
      url: 'https://api.openai.com/v1/models',
      authentication: { type: 'BEARER_TOKEN', token: 'sk-test' },
    }));
  });

  it('sends no auth header when the key is empty (local servers)', async () => {
    sendRequest.mockResolvedValue({ body: { data: [] } });

    await openaiCompatibleClient.listModels({ baseUrl: 'http://localhost:11434/v1', apiKey: ' ' });

    expect(sendRequest.mock.calls[0][0]).not.toHaveProperty('authentication');
  });
});

describe('openaiCompatibleClient.describeError', () => {
  it('maps 401 with the provider message', () => {
    const error = new HttpError({}, { status: 401, responseBody: { error: { message: 'Incorrect API key provided' } } });

    expect(openaiCompatibleClient.describeError(error)).toBe('The API key was rejected. Check the key in the connection. Provider said: Incorrect API key provided');
  });

  it('hints at "Don\'t send" on 400 and trims long provider text', () => {
    const error = new HttpError({}, { status: 400, responseBody: { error: 'x'.repeat(1000) } });
    const message = openaiCompatibleClient.describeError(error);

    expect(message).toContain('Don\'t send');
    expect(message.length).toBeLessThan(600);
  });

  it('passes through non-HTTP errors', () => {
    expect(openaiCompatibleClient.describeError(new Error('ECONNREFUSED'))).toBe('ECONNREFUSED');
  });
});

describe('model dropdown and connection validation', () => {
  beforeEach(() => {
    sendRequest.mockReset();
  });

  it('asks for a connection first', async () => {
    expect(await modelOptions.loadModelOptions({ auth: undefined })).toMatchObject({ disabled: true, placeholder: 'Choose a connection first' });
  });

  it('lists live models as options', async () => {
    sendRequest.mockResolvedValue({ body: { data: [{ id: 'deepseek-chat', owned_by: 'deepseek' }] } });

    const state = await modelOptions.loadModelOptions({ auth: { props: { baseUrl: 'https://api.deepseek.com/v1', apiKey: 'k' } } });

    expect(state).toEqual({ disabled: false, placeholder: 'Select a model', options: [{ label: 'deepseek-chat (deepseek)', value: 'deepseek-chat' }] });
  });

  it('shows why models could not load', async () => {
    sendRequest.mockImplementation(async () => {
      throw new HttpError({}, { status: 404, responseBody: 'not found' });
    });

    const state = await modelOptions.loadModelOptions({ auth: { props: { baseUrl: 'https://wrong.example.com', apiKey: 'k' } } });

    expect(state.disabled).toBe(true);
    expect(state.placeholder).toContain('check the Base URL');
  });

  it('validate accepts an endpoint that lists models and rejects a bad key', async () => {
    sendRequest.mockResolvedValueOnce({ body: { data: [{ id: 'm' }] } });
    expect(await openaiCompatibleAuth.validate?.({ auth: { baseUrl: 'https://x.example.com/v1', apiKey: 'k' }, server: { apiUrl: '', publicUrl: '' } })).toEqual({ valid: true });

    sendRequest.mockRejectedValueOnce(new HttpError({}, { status: 401, responseBody: {} }));
    const result = await openaiCompatibleAuth.validate?.({ auth: { baseUrl: 'https://x.example.com/v1', apiKey: 'bad' }, server: { apiUrl: '', publicUrl: '' } });
    expect(result).toEqual({ valid: false, error: 'The API key was rejected. Check the key in the connection.' });
  });
});
