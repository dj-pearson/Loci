import { Hono } from 'hono';
import { authRateLimit, verifyLimits } from '../middleware/auth-rate-limit.js';

const app = new Hono();

// GET /api/auth/verify-limits?email=user@example.com
// Public endpoint — rate-limited by IP via the auth rate limiter.
// Returns lockout status for pre-flight check by iOS client.
app.get('/verify-limits', verifyLimits);

export default app;
