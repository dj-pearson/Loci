import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { ApnsRequest, ApnsResponse } from '../src/lib/apns.js';

interface UserRow {
  id: string;
  display_name: string;
  apns_token: string | null;
}

interface Recorded {
  table: string;
  op: string;
  payload?: unknown;
  filters: Array<[string, unknown]>;
}

/**
 * Purpose-built supabase fake: the digest route uses a different builder shape
 * from the other routes (count-only selects, `.not`, `.order`, `.limit`), so the
 * shared helper would not reflect what it actually calls.
 */
function digestFake(users: UserRow[], weeklyCount = 2, totalCount = 7) {
  const recorded: Recorded[] = [];

  const client = {
    from(table: string) {
      const filters: Array<[string, unknown]> = [];
      let op = 'select';
      let payload: unknown;
      let countOnly = false;
      let selectedColumns = '';

      const settle = () => {
        recorded.push({ table, op, payload, filters: [...filters] });

        if (op === 'update') return { error: null };
        if (table === 'users') return { data: users, error: null };
        if (countOnly) {
          // The route asks for two different counts against `loci`; the archived
          // filter distinguishes the total from the weekly figure.
          const isTotal = filters.some(([column]) => column === 'is_archived');
          return { count: isTotal ? totalCount : weeklyCount, error: null };
        }
        if (selectedColumns.includes('location_name')) {
          return {
            data: [{ location_name: 'Main Street' }, { location_name: 'Main Street' }],
            error: null,
          };
        }
        return { data: [], error: null };
      };

      const chain: Record<string, unknown> = {
        select(columns: string, opts?: { count?: string; head?: boolean }) {
          op = 'select';
          selectedColumns = columns;
          countOnly = Boolean(opts?.count);
          return chain;
        },
        update(values: unknown) {
          op = 'update';
          payload = values;
          return chain;
        },
        eq(column: string, value: unknown) {
          filters.push([column, value]);
          return chain;
        },
        gte(column: string, value: unknown) {
          filters.push([column, value]);
          return chain;
        },
        not(column: string, ...rest: unknown[]) {
          filters.push([column, rest]);
          return chain;
        },
        order() {
          return chain;
        },
        limit() {
          return chain;
        },
        then(resolve: (value: unknown) => unknown) {
          return Promise.resolve(settle()).then(resolve);
        },
      };
      return chain;
    },
  };

  return { client, recorded };
}

let fake: ReturnType<typeof digestFake>;

vi.mock('../src/middleware/auth.js', () => ({
  getSupabaseAdmin: () => fake.client,
  authMiddleware: async (_c: unknown, next: () => Promise<void>) => next(),
}));

async function loadGenerateDigests() {
  vi.resetModules();
  return (await import('../src/routes/push-digest.js')).generateDigests;
}

function transportReturning(responses: ApnsResponse[]) {
  const seen: ApnsRequest[] = [];
  let index = 0;
  return {
    seen,
    transport: async (request: ApnsRequest) => {
      seen.push(request);
      const response = responses[Math.min(index, responses.length - 1)];
      index += 1;
      return response;
    },
  };
}

const apnsConfig = {
  // A syntactically valid P-256 key generated once for the suite.
  keyP8: '',
  keyId: 'KEYID12345',
  teamId: 'TEAMID1234',
  topic: 'app.lociate.ios',
  host: 'https://api.sandbox.push.apple.com',
};

beforeEach(async () => {
  const { generateKeyPairSync } = await import('node:crypto');
  const { privateKey } = generateKeyPairSync('ec', {
    namedCurve: 'prime256v1',
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
    publicKeyEncoding: { type: 'spki', format: 'pem' },
  }) as unknown as { privateKey: string };
  apnsConfig.keyP8 = privateKey;
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.resetModules();
});

describe('generateDigests', () => {
  it('sends one digest per eligible user and reports the count', async () => {
    fake = digestFake([{ id: 'u1', display_name: 'A', apns_token: 'tok-1' }]);
    const { transport, seen } = transportReturning([{ status: 200, body: '' }]);
    const generateDigests = await loadGenerateDigests();

    const result = await generateDigests({ config: apnsConfig, transport });

    expect(result).toEqual({ sent: 1, skipped: 0, invalidated: 0 });
    expect(seen).toHaveLength(1);
    expect(seen[0].path).toBe('/3/device/tok-1');
    // The body should carry the computed weekly/total figures.
    const body = JSON.parse(seen[0].body);
    expect(body.aps.alert.body).toContain('2 loci this week');
    expect(body.aps.alert.body).toContain('Total: 7 loci');
    expect(body.aps.alert.body).toContain('Most visited: Main Street');
  });

  it('clears the stored token when APNs says the device is unregistered', async () => {
    // Previously nothing could clear a dead token, because the sender always
    // reported success — so the same dead token was retried every week forever.
    fake = digestFake([{ id: 'u1', display_name: 'A', apns_token: 'dead-token' }]);
    const { transport } = transportReturning([
      { status: 410, body: JSON.stringify({ reason: 'Unregistered' }) },
    ]);
    const generateDigests = await loadGenerateDigests();

    const result = await generateDigests({ config: apnsConfig, transport, sleep: async () => {} });

    expect(result).toEqual({ sent: 0, skipped: 0, invalidated: 1 });
    const update = fake.recorded.find((r) => r.table === 'users' && r.op === 'update');
    expect(update?.payload).toEqual({ apns_token: null });
    expect(update?.filters).toEqual([['id', 'u1']]);
  });

  it('counts a transient failure as skipped and leaves the token in place', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    fake = digestFake([{ id: 'u1', display_name: 'A', apns_token: 'tok-1' }]);
    const { transport } = transportReturning([{ status: 503, body: '' }]);
    const generateDigests = await loadGenerateDigests();

    const result = await generateDigests({
      config: apnsConfig,
      transport,
      sleep: async () => {},
      maxAttempts: 2,
    });

    expect(result).toEqual({ sent: 0, skipped: 1, invalidated: 0 });
    expect(fake.recorded.some((r) => r.op === 'update')).toBe(false);
  });

  it('does not report deliveries when APNs is not configured', async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    fake = digestFake([{ id: 'u1', display_name: 'A', apns_token: 'tok-1' }]);
    const generateDigests = await loadGenerateDigests();

    const result = await generateDigests({ config: null });

    expect(result).toEqual({ sent: 0, skipped: 1, invalidated: 0 });
  });

  it('skips users with no token without contacting APNs', async () => {
    fake = digestFake([{ id: 'u1', display_name: 'A', apns_token: null }]);
    const { transport, seen } = transportReturning([{ status: 200, body: '' }]);
    const generateDigests = await loadGenerateDigests();

    const result = await generateDigests({ config: apnsConfig, transport });

    expect(result).toEqual({ sent: 0, skipped: 1, invalidated: 0 });
    expect(seen).toHaveLength(0);
  });

  it('skips users with no recent activity', async () => {
    fake = digestFake([{ id: 'u1', display_name: 'A', apns_token: 'tok-1' }], 0, 0);
    const { transport, seen } = transportReturning([{ status: 200, body: '' }]);
    const generateDigests = await loadGenerateDigests();

    const result = await generateDigests({ config: apnsConfig, transport });

    expect(result.sent).toBe(0);
    expect(seen).toHaveLength(0);
  });

  it('returns zeroed counts when there are no users at all', async () => {
    fake = digestFake([]);
    const generateDigests = await loadGenerateDigests();

    await expect(generateDigests({ config: apnsConfig })).resolves.toEqual({
      sent: 0,
      skipped: 0,
      invalidated: 0,
    });
  });
});
