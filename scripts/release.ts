#!/usr/bin/env bun

/**
 * Build, sign, notarize, and publish the apple-reminders release to
 * npm and GitHub.
 *
 * The version comes from npm/package.json — bump it manually (and
 * Sources/AppleRemindersCore/Version.swift to match) before running.
 *
 * Prerequisites (one-time setup):
 *
 *   1. Apple Developer ID Application certificate installed in the keychain.
 *      Verify with: `security find-identity -v -p codesigning | grep "Developer ID Application"`
 *
 *   2. notarytool credentials stored in the keychain. From a one-time setup:
 *        xcrun notarytool store-credentials apple-reminders \
 *          --apple-id <you@example.com> \
 *          --team-id <TEAM_ID> \
 *          --password <app-specific-password>
 *      (App-specific password from https://appleid.apple.com → Sign-In and Security → App-Specific Passwords.)
 *
 *   3. `gh` CLI authenticated: `gh auth login`
 *
 *   4. `npm` logged in to a publisher of the @justinhaaheim scope: `npm login`
 *
 * Environment variables (per release):
 *
 *   SIGNING_IDENTITY  Codesign identity name, e.g.
 *                     "Developer ID Application: Justin Haaheim (TEAMID)"
 *   NOTARY_PROFILE    notarytool keychain profile name from step 2
 *                     (default: "apple-reminders")
 *
 * Usage:
 *   bun run release                  # full release
 *   bun run release --dry-run        # build + sign + notarize, no publish/tag/release
 *   bun run release --skip-build     # reuse the existing npm/bin/reminders
 *   bun run release --skip-notarize  # skip notarization (e.g. retrying publish)
 */

import {$} from 'bun';
import {existsSync, readFileSync, chmodSync, statSync} from 'node:fs';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const NPM_DIR = join(REPO_ROOT, 'npm');
const NPM_BIN = join(NPM_DIR, 'bin', 'reminders');
const NOTARIZE_ZIP = join(REPO_ROOT, '.build', 'release-notarize.zip');

const {values} = parseArgs({
  args: process.argv.slice(2),
  options: {
    'dry-run': {type: 'boolean'},
    'skip-build': {type: 'boolean'},
    'skip-notarize': {type: 'boolean'},
  },
});
const DRY_RUN = values['dry-run'] ?? false;
const SKIP_BUILD = values['skip-build'] ?? false;
const SKIP_NOTARIZE = values['skip-notarize'] ?? false;

function fail(msg: string): never {
  console.error(`\nerror: ${msg}`);
  process.exit(1);
}

function step(label: string): void {
  console.log(`\n==> ${label}`);
}

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) {
    fail(
      `${name} must be set. See the header of scripts/release.ts for prerequisites.`,
    );
  }
  return v;
}

// === 1. Load version from npm/package.json ===
const pkgPath = join(NPM_DIR, 'package.json');
const pkg = JSON.parse(readFileSync(pkgPath, 'utf-8')) as {
  name: string;
  version: string;
};
const {name: pkgName, version} = pkg;
const tag = `v${version}`;

console.log(`Releasing ${pkgName}@${version} (tag ${tag})`);
console.log(
  `  dry-run=${DRY_RUN}  skip-build=${SKIP_BUILD}  skip-notarize=${SKIP_NOTARIZE}`,
);

// === 2. Preflight ===
step('Preflight');

const dirty = (await $`git status --porcelain`.text()).trim();
if (dirty !== '') {
  console.error(dirty);
  fail('working tree not clean. Commit or stash changes first.');
}

const tagExists = (await $`git tag --list ${tag}`.text()).trim();
if (tagExists !== '' && !DRY_RUN) {
  fail(
    `tag ${tag} already exists. Bump npm/package.json (and Version.swift) first.`,
  );
}

const swiftVersion = readFileSync(
  join(REPO_ROOT, 'Sources/AppleRemindersCore/Version.swift'),
  'utf-8',
).match(/appVersion = "([^"]+)"/)?.[1];
if (swiftVersion && swiftVersion !== version) {
  fail(
    `Version.swift (${swiftVersion}) does not match npm/package.json (${version}). ` +
      `Sync them before releasing.`,
  );
}

if (!DRY_RUN) {
  try {
    await $`npm whoami --registry=https://registry.npmjs.org`.quiet();
  } catch {
    fail('npm not logged in. Run `npm login` first.');
  }
  try {
    await $`gh auth status`.quiet();
  } catch {
    fail('gh CLI not authenticated. Run `gh auth login` first.');
  }
}

const SIGNING_IDENTITY = requireEnv('SIGNING_IDENTITY');
const NOTARY_PROFILE = SKIP_NOTARIZE
  ? ''
  : (process.env.NOTARY_PROFILE ?? 'apple-reminders');

// === 3. Build universal binary ===
if (SKIP_BUILD) {
  if (!existsSync(NPM_BIN)) {
    fail(`--skip-build but no binary at ${NPM_BIN}`);
  }
  console.log(`\n==> Skipping build, using existing ${NPM_BIN}`);
} else {
  step('Build universal binary');
  // Delegates to the existing scripts/build-universal.ts which lipo's
  // arm64 + x86_64 builds into npm/bin/reminders.
  await $`bun scripts/build-universal.ts --check`.cwd(REPO_ROOT);
}

if (!existsSync(NPM_BIN)) {
  fail(`expected universal binary at ${NPM_BIN} but it's missing`);
}

step('Verify binary is universal');
const lipoInfo = (await $`lipo -info ${NPM_BIN}`.text()).trim();
console.log(`   ${lipoInfo}`);
if (!lipoInfo.includes('arm64') || !lipoInfo.includes('x86_64')) {
  fail('binary is not universal — expected both arm64 and x86_64 slices');
}
const size = statSync(NPM_BIN).size;
console.log(`   size: ${(size / 1024 / 1024).toFixed(2)} MiB`);

// === 4. Codesign ===
step(`Codesign (${SIGNING_IDENTITY})`);
await $`codesign --sign ${SIGNING_IDENTITY} --options runtime --timestamp --force ${NPM_BIN}`;
await $`codesign --verify --verbose ${NPM_BIN}`;

// === 5. Notarize ===
if (SKIP_NOTARIZE) {
  console.log('\n==> Skipping notarization (--skip-notarize)');
} else {
  step('Zip for notarization');
  await $`rm -f ${NOTARIZE_ZIP}`.quiet();
  await $`ditto -c -k --keepParent ${NPM_BIN} ${NOTARIZE_ZIP}`;

  step(
    `Submit for notarization (profile=${NOTARY_PROFILE}; this can take a few minutes)`,
  );
  await $`xcrun notarytool submit ${NOTARIZE_ZIP} --keychain-profile ${NOTARY_PROFILE} --wait`;
  // Stapling isn't supported for bare CLI binaries — Gatekeeper
  // checks notarization status online instead. That's fine for a CLI.
}

chmodSync(NPM_BIN, 0o755);

if (DRY_RUN) {
  console.log(
    '\n✓ Dry run complete. Skipping npm publish, git tag, and GitHub release.',
  );
  console.log(`   Binary:  ${NPM_BIN}`);
  if (!SKIP_NOTARIZE) console.log(`   Zip:     ${NOTARIZE_ZIP}`);
  process.exit(0);
}

// === 6. Publish to npm ===
step(`Publish ${pkgName}@${version} to npm`);
await $`npm publish --access=public`.cwd(NPM_DIR);

// === 7. Tag + push ===
step(`Create git tag ${tag} and push`);
await $`git tag -a ${tag} -m ${`Release ${version}`}`;
await $`git push origin ${tag}`;

// === 8. GitHub release ===
step(`Create GitHub release ${tag}`);
const zipForRelease = SKIP_NOTARIZE ? '' : NOTARIZE_ZIP;
if (zipForRelease) {
  await $`gh release create ${tag} ${zipForRelease} --title ${`apple-reminders ${version}`} --generate-notes`;
} else {
  await $`gh release create ${tag} --title ${`apple-reminders ${version}`} --generate-notes`;
}

console.log(`\n✓ Released ${pkgName}@${version}`);
console.log(`   npm:    https://www.npmjs.com/package/${pkgName}`);
console.log(
  `   github: https://github.com/justinhaaheim/apple-reminders-mcp/releases/tag/${tag}`,
);
