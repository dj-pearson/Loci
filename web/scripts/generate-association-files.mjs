#!/usr/bin/env node
/**
 * Writes the platform association files into web/public/.well-known/ (US-203).
 *
 * The committed AASA file contained the literal string `TEAM_ID`, which makes
 * every iOS universal link fail silently, and there was no assetlinks.json at
 * all, so Android App Links could not be verified. Both are generated from
 * environment variables at build time so the real values live in the Cloudflare
 * Pages project settings rather than in the repo.
 *
 *   APPLE_TEAM_ID          10-char Apple Developer Team ID (e.g. A1B2C3D4E5)
 *   ANDROID_SHA256_CERT_FP Play App Signing SHA-256 fingerprint, colon-separated
 *
 * In production (CF_PAGES=1 or NODE_ENV=production) a missing value is a hard
 * error: shipping a placeholder is worse than failing the build, because broken
 * universal links look like an app bug rather than a deploy bug.
 */

import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const wellKnown = resolve(here, '..', 'public', '.well-known');

const IOS_BUNDLE_ID = 'app.lociate.ios';
const ANDROID_PACKAGE = 'app.lociate.android';
const PATHS = ['/open/*', '/locus/*'];

const isProduction =
  process.env.CF_PAGES === '1' || process.env.NODE_ENV === 'production';

function required(name, placeholder) {
  const value = process.env[name];
  if (value && value.trim()) return value.trim();

  if (isProduction) {
    console.error(
      `[association] ${name} is not set. Universal links / App Links cannot be ` +
        `verified without it. Set it in the Cloudflare Pages project settings.`
    );
    process.exit(1);
  }

  console.warn(
    `[association] ${name} is not set — writing a development placeholder. ` +
      `Deep links will NOT verify against this file.`
  );
  return placeholder;
}

const teamId = required('APPLE_TEAM_ID', 'DEVTEAMID0');
const fingerprint = required(
  'ANDROID_SHA256_CERT_FP',
  'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:' +
    'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99'
);

const aasa = {
  applinks: {
    // `apps` must be present and empty — Apple's spec, not a placeholder.
    apps: [],
    details: [
      {
        appID: `${teamId}.${IOS_BUNDLE_ID}`,
        paths: PATHS,
      },
    ],
  },
  webcredentials: {
    apps: [`${teamId}.${IOS_BUNDLE_ID}`],
  },
};

const assetlinks = [
  {
    relation: ['delegate_permission/common.handle_all_urls'],
    target: {
      namespace: 'android_app',
      package_name: ANDROID_PACKAGE,
      // Must be the Play App Signing certificate, not the local upload keystore —
      // Play re-signs the bundle, so the upload fingerprint never matches in
      // production.
      sha256_cert_fingerprints: [fingerprint.toUpperCase()],
    },
  },
];

mkdirSync(wellKnown, { recursive: true });

writeFileSync(
  resolve(wellKnown, 'apple-app-site-association'),
  `${JSON.stringify(aasa, null, 2)}\n`
);
writeFileSync(
  resolve(wellKnown, 'assetlinks.json'),
  `${JSON.stringify(assetlinks, null, 2)}\n`
);

console.log('[association] wrote apple-app-site-association and assetlinks.json');
