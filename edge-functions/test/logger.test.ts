import { Hono } from 'hono';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  errorFields,
  log,
  requestLogger,
  runScheduledJob,
  type RequestLogEnv,
} from '../src/lib/logger.js';

/**
 * Captures emitted lines as parsed objects, per stream.
 *
 * Non-JSON lines are kept separately rather than throwing: Hono's own internals
 * write plain text to console.error, and a harness that assumes everything is
 * JSON fails on library output instead of on the code under test.
 */
function captureLogs() {
  const out: Array<Record<string, unknown>> = [];
  const err: Array<Record<string, unknown>> = [];
  const raw: string[] = [];

  const push = (target: Array<Record<string, unknown>>) => (line: unknown) => {
    if (typeof line !== 'string') {
      raw.push(String(line));
      return;
    }
    try {
      target.push(JSON.parse(line));
    } catch {
      raw.push(line);
    }
  };

  vi.spyOn(console, 'log').mockImplementation(push(out));
  vi.spyOn(console, 'error').mockImplementation(push(err));
  return { out, err, raw, all: () => [...out, ...err] };
}

beforeEach(() => {
  delete process.env.LOG_LEVEL;
});

afterEach(() => {
  vi.restoreAllMocks();
  delete process.env.LOG_LEVEL;
});

describe('structured logging', () => {
  it('emits one JSON object per line with a stable envelope', () => {
    const logs = captureLogs();

    log.info('something happened', { locusId: 'abc' });

    expect(logs.out).toHaveLength(1);
    expect(logs.out[0]).toMatchObject({
      level: 'info',
      msg: 'something happened',
      service: 'lociate-edge',
      locusId: 'abc',
    });
    expect(typeof logs.out[0].time).toBe('string');
  });

  it('sends warn and error to stderr so log drivers can split streams', () => {
    const logs = captureLogs();

    log.info('routine');
    log.warn('suspicious');
    log.error('broken');

    expect(logs.out.map((l) => l.level)).toEqual(['info']);
    expect(logs.err.map((l) => l.level)).toEqual(['warn', 'error']);
  });

  it('honours LOG_LEVEL', () => {
    process.env.LOG_LEVEL = 'warn';
    const logs = captureLogs();

    log.debug('d');
    log.info('i');
    log.warn('w');

    expect(logs.all().map((l) => l.level)).toEqual(['warn']);
  });

  it('redacts credential-bearing keys anywhere in the payload', () => {
    // Key-based, not value-based: a token's shape is not reliably detectable, and
    // one leaked Authorization header in an aggregator is a credential disclosure.
    const logs = captureLogs();

    log.info('request', {
      authorization: 'Bearer secret-jwt',
      headers: { cookie: 'session=abc', 'x-request-signature': 'deadbeef' },
      user: { apns_token: 'device-token', id: 'safe-to-log' },
      invite_code: 'AB12CD34',
      transcription: 'the spare key is under the mat',
    });

    const line = logs.out[0] as Record<string, any>;
    expect(line.authorization).toBe('[redacted]');
    expect(line.headers.cookie).toBe('[redacted]');
    expect(line.headers['x-request-signature']).toBe('[redacted]');
    expect(line.user.apns_token).toBe('[redacted]');
    expect(line.user.id).toBe('safe-to-log');
    expect(line.invite_code).toBe('[redacted]');
    // Voice-note content is the most sensitive thing the app holds.
    expect(line.transcription).toBe('[redacted]');
    expect(JSON.stringify(line)).not.toContain('secret-jwt');
    expect(JSON.stringify(line)).not.toContain('under the mat');
  });

  it('redacts case-insensitively', () => {
    const logs = captureLogs();
    log.info('x', { Authorization: 'Bearer y', APNS_TOKEN: 'z' });

    expect(logs.out[0]).toMatchObject({
      Authorization: '[redacted]',
      APNS_TOKEN: '[redacted]',
    });
  });

  it('does not recurse without bound on deep or cyclic-shaped payloads', () => {
    const logs = captureLogs();
    let deep: Record<string, unknown> = { value: 'leaf' };
    for (let i = 0; i < 20; i += 1) deep = { nested: deep };

    expect(() => log.info('deep', deep)).not.toThrow();
    expect(logs.out).toHaveLength(1);
  });

  it('serializes Error objects with a bounded stack', () => {
    const fields = errorFields(new Error('boom'));

    expect(fields).toMatchObject({ error: 'boom', errorName: 'Error' });
    expect(String(fields.stack).split('\n').length).toBeLessThanOrEqual(8);
  });

  it('serializes non-Error throws', () => {
    expect(errorFields('just a string')).toEqual({ error: 'just a string' });
  });
});

describe('requestLogger', () => {
  /** Mirrors the real app in src/index.ts, including its onError handler. */
  function app() {
    const instance = new Hono<RequestLogEnv>();
    instance.use('*', requestLogger);
    instance.onError((error, c) => {
      log.error('unhandled route error', {
        requestId: c.get('requestId'),
        route: new URL(c.req.url).pathname,
        ...errorFields(error),
      });
      return c.json({ error: 'Internal server error' }, 500);
    });
    instance.get('/ok', (c) => c.json({ ok: true }));
    instance.get('/missing', (c) => c.json({ error: 'nope' }, 404));
    instance.get('/broken', () => {
      throw new Error('handler exploded');
    });
    return instance;
  }

  it('logs one line per request with method, route, status, and duration', async () => {
    const logs = captureLogs();

    const response = await app().request('/ok');

    expect(response.status).toBe(200);
    const line = logs.out.find((l) => l.msg === 'request') as Record<string, unknown>;
    expect(line).toMatchObject({ level: 'info', method: 'GET', route: '/ok', status: 200 });
    expect(typeof line.durationMs).toBe('number');
  });

  it('echoes a correlation id so a reported failure can be traced', async () => {
    captureLogs();

    const response = await app().request('/ok');
    const id = response.headers.get('X-Request-Id');

    expect(id).toBeTruthy();
    expect(id).toMatch(/^[0-9a-f-]{36}$/);
  });

  it('preserves an upstream request id end to end', async () => {
    const logs = captureLogs();

    const response = await app().request('/ok', {
      headers: { 'x-request-id': 'upstream-id-123' },
    });

    expect(response.headers.get('X-Request-Id')).toBe('upstream-id-123');
    expect(logs.out.find((l) => l.msg === 'request')).toMatchObject({
      requestId: 'upstream-id-123',
    });
  });

  it('logs a 4xx at warn and a 5xx at error', async () => {
    const logs = captureLogs();

    await app().request('/missing');

    expect(logs.err.find((l) => l.msg === 'request')).toMatchObject({
      level: 'warn',
      status: 404,
    });
  });

  it('logs a handler error and returns a 500 without leaking the message', async () => {
    const logs = captureLogs();

    const response = await app().request('/broken');

    expect(response.status).toBe(500);
    // The client must not see internals; the detail belongs in the log only.
    await expect(response.json()).resolves.toEqual({ error: 'Internal server error' });

    // Hono routes the throw through onError before returning to the request
    // logger, so the detail comes from that handler...
    const handled = logs.err.find((l) => l.msg === 'unhandled route error');
    expect(handled).toMatchObject({ route: '/broken', error: 'handler exploded' });

    // ...and the request line still records the outcome at error severity.
    expect(logs.err.find((l) => l.msg === 'request')).toMatchObject({
      level: 'error',
      route: '/broken',
      status: 500,
    });
  });
});

describe('runScheduledJob', () => {
  it('logs start and completion with the job result merged in', async () => {
    const logs = captureLogs();

    const result = await runScheduledJob('push-digest', async () => ({
      sent: 3,
      skipped: 1,
    }));

    expect(result).toEqual({ sent: 3, skipped: 1 });
    expect(logs.out.map((l) => l.msg)).toEqual(['cron started', 'cron completed']);
    expect(logs.out[1]).toMatchObject({ job: 'push-digest', sent: 3, skipped: 1 });
    expect(typeof logs.out[1].durationMs).toBe('number');
  });

  it('records a failed run instead of letting it vanish', async () => {
    // A cron that threw previously logged nothing and the run simply disappeared.
    const logs = captureLogs();
    const onError = vi.fn();

    const result = await runScheduledJob(
      'analyze-loci',
      async () => {
        throw new Error('anthropic 503');
      },
      { onError }
    );

    expect(result).toBeUndefined();
    expect(logs.err[0]).toMatchObject({
      level: 'error',
      msg: 'cron failed',
      job: 'analyze-loci',
      error: 'anthropic 503',
    });
    expect(onError).toHaveBeenCalledOnce();
  });

  it('does not let a failing job take down the scheduler', async () => {
    captureLogs();
    await expect(
      runScheduledJob('boom', async () => {
        throw new Error('x');
      })
    ).resolves.toBeUndefined();
  });
});
