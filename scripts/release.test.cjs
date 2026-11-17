const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { plan, updatePubspec, sourcePlan, prepare, changelog, publish } = require('./release.cjs');

const sha = 'a'.repeat(40);
function context(overrides = {}) {
  return {
    repo: { owner: 'owner', repo: 'companion' },
    payload: {
      repository: { default_branch: 'main' },
      workflow_run: {
        id: 42, run_number: 1, run_attempt: 1, head_sha: sha, head_branch: 'main',
        path: '.github/workflows/ci.yml', conclusion: 'success', event: 'push',
        repository: { full_name: 'owner/companion' }, ...overrides,
      },
    },
  };
}
const notFound = () => Promise.reject(Object.assign(new Error('Not found'), { status: 404 }));
const core = { notice() {}, setOutput() {} };

test('every new run increments both release version and Android versionCode', () => {
  assert.deepEqual([plan(1).tag, plan(1).versionName, plan(1).versionCode], ['v1.2', '1.2.0', 4]);
  const tags = new Set();
  for (let run = 1; run <= 1000; run++) {
    const current = plan(run);
    assert(!tags.has(current.tag));
    tags.add(current.tag);
    assert.equal(current.versionCode, run + 3);
  }
  assert.deepEqual(plan(9), plan(9));
  for (const invalid of [0, -1, NaN, 'x', 1.5, 2100000000]) assert.throws(() => plan(invalid));
});

test('the app version follows the release plan and preserves CRLF', () => {
  assert.equal(updatePubspec('name: companion\r\nversion: 1.1.1+3\r\n', plan(2)),
    'name: companion\r\nversion: 1.3.0+5\r\n');
  assert.throws(() => updatePubspec('version: unknown\n', plan(1)));
});

test('source metadata is tied to the successful CI run, including fork PR runs', () => {
  const preview = sourcePlan(context({ event: 'pull_request', head_branch: 'feature', run_attempt: 2 }));
  assert.equal(preview.prerelease, true);
  assert.equal(preview.artifact, 'Companion-unsigned-42-2');
  for (const invalid of [{ conclusion: 'failure' }, { path: '.github/workflows/other.yml' },
    { repository: { full_name: 'attacker/fork' } }, { event: 'push', head_branch: 'feature' },
    { event: 'pull_request_target' }, { head_sha: '$(bad)' }, { id: -1 }, { run_attempt: 0 }]) {
    assert.throws(() => sourcePlan(context(invalid)));
  }
});

test('reruns leave published releases unchanged and refuse tag collisions', async () => {
  const outputs = {};
  const github = { rest: { git: {
    getRef: async () => ({ data: { object: { type: 'commit', sha } } }),
  }, repos: { getReleaseByTag: async () => ({ data: { draft: false } }) } } };
  await prepare({ github, context: context(), core: { ...core, setOutput(name, value) { outputs[name] = value; } } });
  assert.equal(outputs.skip, true);
  github.rest.git.getRef = async () => ({ data: { object: { type: 'commit', sha: 'b'.repeat(40) } } });
  await assert.rejects(prepare({ github, context: context(), core }), /never be moved/);
});

test('changelogs use commit subjects, links, and the prior stable release', async () => {
  const requests = [];
  const github = { rest: { repos: { compareCommitsWithBasehead: async request => {
    requests.push(request);
    return { data: { commits: [{ sha, commit: { message: 'fix: restore [titles]\n\nLong explanation' } }] } };
  } } } };
  const release = { ...plan(3), sha, prerelease: false };
  const notes = await changelog(github, context(), release, [
    { tag_name: 'v1.2', draft: false, prerelease: false },
    { tag_name: 'v1.3', draft: false, prerelease: true },
    { tag_name: 'v1.5', draft: false, prerelease: false },
  ]);
  assert.equal(requests[0].basehead, `v1.2...${sha}`);
  assert.match(notes, /## Changelog/);
  assert(notes.includes('fix: restore \\[titles\\]'));
  assert(!notes.includes('Long explanation'));
  await changelog(github, context(), { ...release, prerelease: true }, []);
  assert.equal(requests[1].basehead, `main...${sha}`);
});

test('an unpublished draft is recovered through the releases list', async () => {
  const outputs = {};
  const github = { rest: { git: {
    getRef: async () => ({ data: { object: { type: 'commit', sha } } }),
  }, repos: { getReleaseByTag: notFound, listReleases() {} } },
    paginate: async () => [{ tag_name: 'v1.2', draft: true }] };
  await prepare({ github, context: context(), core: { ...core, setOutput(name, value) { outputs[name] = value; } } });
  assert.equal(outputs.skip, false);
});

test('publication uploads APK, changelog and hashes before making the draft public', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'companion-release-test-'));
  const events = [];
  const github = { rest: { git: {
    getRef: notFound,
    createRef: async request => { events.push(['tag', request]); },
  }, repos: {
    getReleaseByTag: notFound, listReleases() {},
    listCommits: async () => ({ data: [{ sha, commit: { message: 'feat: first release' } }] }),
    createRelease: async request => {
      events.push(['draft', request]);
      return { data: { id: 1, assets: [] } };
    },
    uploadReleaseAsset: async request => { events.push(['asset', request]); },
    updateRelease: async request => { events.push(['public', request]); },
  } }, paginate: async () => [] };
  try {
    fs.writeFileSync(path.join(directory, plan(1).apk), 'test APK');
    await publish({ github, context: context(), core, directory });
    assert.deepEqual(events.map(([type]) => type), ['tag', 'draft', 'asset', 'asset', 'asset', 'public']);
    assert.equal(events[1][1].draft, true);
    assert.equal(events.at(-1)[1].draft, false);
    assert.equal(events.at(-1)[1].make_latest, 'true');
    assert.match(fs.readFileSync(path.join(directory, 'SHA256SUMS.txt'), 'utf8'), /  CHANGELOG.md/);
    events.length = 0;
    github.rest.git.getRef = async () => ({ data: { object: { type: 'commit', sha } } });
    github.rest.repos.getReleaseByTag = async () => ({ data: { draft: false } });
    await publish({ github, context: context(), core, directory });
    assert.deepEqual(events, []);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('an interrupted draft never overwrites an existing different asset', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'companion-release-test-'));
  const github = { rest: { git: {
    getRef: async () => ({ data: { object: { type: 'commit', sha } } }),
  }, repos: {
    listReleases() {},
    getReleaseByTag: async () => ({ data: { id: 2, draft: true, body: 'Original notes',
      assets: [{ name: plan(1).apk, state: 'uploaded', digest: 'sha256:different' }] } }),
  } }, paginate: async () => [] };
  try {
    fs.writeFileSync(path.join(directory, plan(1).apk), 'test APK');
    await assert.rejects(publish({ github, context: context(), core, directory }), /Refusing to overwrite/);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});
