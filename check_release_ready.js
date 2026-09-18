const { execSync } = require('child_process');

// Guards against `npm run release:*` leaving a stray local commit/tag behind
// when it can't push: run before increment_version.js so no state has been
// mutated yet if a check fails.

function run(cmd) {
    return execSync(cmd, { encoding: 'utf8' }).trim();
}

function fail(message) {
    console.error(`Error: ${message}`);
    process.exit(1);
}

const branch = run('git rev-parse --abbrev-ref HEAD');
if (branch !== 'main') {
    fail(`releases must be run from 'main' (currently on '${branch}').`);
}

const status = run('git status --porcelain');
if (status) {
    fail("working tree is not clean. Commit or stash your changes before releasing.");
}

try {
    run('git fetch origin main --quiet');
} catch (e) {
    fail(`could not fetch 'origin/main': ${e.message}`);
}

const local = run('git rev-parse main');
const remote = run('git rev-parse origin/main');
if (local !== remote) {
    fail("local 'main' is not up to date with 'origin/main'. Pull/rebase before releasing.");
}

console.log("✓ Release preflight checks passed (on main, clean tree, up to date with origin).");
