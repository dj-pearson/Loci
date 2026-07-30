import { vi } from 'vitest';

/**
 * Minimal stand-in for the parts of the supabase-js client the routes touch.
 *
 * The real client cannot be used in tests (no server, and constructing it needs
 * live credentials), and mocking per-call would hide the chained builder shape
 * the routes actually rely on. This records every operation so assertions can
 * check *what* was deleted or updated, not just that something was.
 */

export interface RecordedOp {
  table: string;
  op: 'select' | 'update' | 'delete';
  filters: Array<[string, unknown]>;
  payload?: unknown;
}

export interface StorageOp {
  bucket: string;
  op: 'list' | 'remove';
  arg: unknown;
}

type ErrorLike = { message: string } | null;

export interface FakeOptions {
  /** Rows returned by `select` per table. */
  selectData?: Record<string, unknown[]>;
  /** Force an error from a given `${table}.${op}` key, e.g. 'loci.delete'. */
  errors?: Record<string, string>;
  /** Pages returned by successive storage `list` calls. */
  storagePages?: Array<Array<{ name: string }>>;
  storageListError?: string;
  storageRemoveError?: string;
  deleteUserError?: string;
}

export function createSupabaseFake(options: FakeOptions = {}) {
  const ops: RecordedOp[] = [];
  const storageOps: StorageOp[] = [];
  let storageListCalls = 0;

  const errorFor = (key: string): ErrorLike =>
    options.errors?.[key] ? { message: options.errors[key] } : null;

  function builder(table: string) {
    const filters: Array<[string, unknown]> = [];
    let op: RecordedOp['op'] = 'select';
    let payload: unknown;

    const record = () => {
      ops.push({ table, op, filters: [...filters], payload });
      return { error: errorFor(`${table}.${op}`), data: options.selectData?.[table] ?? [] };
    };

    // `eq` is the terminal call in every route, so it resolves. Chaining works
    // because the object is both thenable and further-chainable.
    const chain: Record<string, unknown> = {
      select(_columns?: string) {
        op = 'select';
        return chain;
      },
      update(values: unknown) {
        op = 'update';
        payload = values;
        return chain;
      },
      delete() {
        op = 'delete';
        return chain;
      },
      eq(column: string, value: unknown) {
        filters.push([column, value]);
        return chain;
      },
      limit() {
        return chain;
      },
      then(resolve: (value: unknown) => unknown) {
        return Promise.resolve(record()).then(resolve);
      },
    };
    return chain;
  }

  const client = {
    from: (table: string) => builder(table),
    storage: {
      from: (bucket: string) => ({
        list: async (prefix: string, opts?: unknown) => {
          storageOps.push({ bucket, op: 'list', arg: { prefix, opts } });
          if (options.storageListError) {
            return { data: null, error: { message: options.storageListError } };
          }
          const page = options.storagePages?.[storageListCalls] ?? [];
          storageListCalls += 1;
          return { data: page, error: null };
        },
        remove: async (paths: string[]) => {
          storageOps.push({ bucket, op: 'remove', arg: paths });
          if (options.storageRemoveError) {
            return { data: null, error: { message: options.storageRemoveError } };
          }
          return { data: paths, error: null };
        },
      }),
    },
    auth: {
      admin: {
        deleteUser: vi.fn(async () => ({
          data: null,
          error: options.deleteUserError ? { message: options.deleteUserError } : null,
        })),
      },
    },
  };

  return {
    client,
    ops,
    storageOps,
    opsFor: (table: string, op: RecordedOp['op']) =>
      ops.filter((o) => o.table === table && o.op === op),
  };
}
