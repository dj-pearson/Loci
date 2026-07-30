#!/usr/bin/env node
/**
 * Container healthcheck (US-215).
 *
 * node:20-alpine ships neither curl nor wget, so the compose healthcheck
 * `curl -f http://localhost:3000/health` failed twice over: the binary was
 * missing, and the route is mounted at /api/health, not /health. The container
 * was therefore permanently unhealthy — which with `restart: always` means a
 * restart loop, and Traefik never routing to it.
 *
 * Exits 0 only on HTTP 200. /api/health returns 503 when a dependency is down,
 * which correctly marks the container unhealthy.
 */
import { get } from 'node:http';

const port = process.env.PORT || '3000';
const timeoutMs = 4000;

const request = get(
  { host: '127.0.0.1', port, path: '/api/health', timeout: timeoutMs },
  (response) => {
    // Drain so the socket closes cleanly rather than leaking a half-open conn.
    response.resume();
    response.on('end', () => process.exit(response.statusCode === 200 ? 0 : 1));
  }
);

request.on('timeout', () => {
  request.destroy();
  process.exit(1);
});
request.on('error', () => process.exit(1));
