import { createMiddleware } from 'hono/factory';
import { createClient } from '@supabase/supabase-js';
import type { Context } from 'hono';

export interface AuthUser {
  id: string;
  email?: string;
}

export interface AuthEnv {
  Variables: {
    user: AuthUser;
    userId: string; // internal users.id
  };
}

function getSupabaseClient() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_KEY;
  if (!url || !key) {
    throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_KEY');
  }
  return createClient(url, key);
}

export const authMiddleware = createMiddleware<AuthEnv>(async (c, next) => {
  const authHeader = c.req.header('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return c.json({ error: 'Missing or invalid Authorization header' }, 401);
  }

  const token = authHeader.slice(7);
  const supabase = getSupabaseClient();

  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (error || !user) {
    return c.json({ error: 'Invalid or expired token' }, 401);
  }

  // Look up the internal user ID
  const { data: profile, error: profileError } = await supabase
    .from('users')
    .select('id')
    .eq('auth_id', user.id)
    .single();

  if (profileError || !profile) {
    return c.json({ error: 'User profile not found' }, 404);
  }

  c.set('user', { id: user.id, email: user.email });
  c.set('userId', profile.id);

  await next();
});

export function getSupabaseAdmin() {
  return getSupabaseClient();
}
