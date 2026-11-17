const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');

// Run 1 starts at 1.2.0+4. Keep these offsets fixed for this major series.
const SERIES = { major: 1, firstMinor: 2, firstBuild: 4 };

function plan(runNumber) {
  const run = Number(runNumber);
  if (!Number.isSafeInteger(run) || run < 1) throw new Error('Invalid CI run number.');
  const version = `${SERIES.major}.${SERIES.firstMinor + run - 1}`;
  const versionCode = SERIES.firstBuild + run - 1;
  if (versionCode > 2100000000) throw new Error('Android versionCode limit exceeded.');
  return {
    version, versionName: `${version}.0`, versionCode,
    tag: `v${version}`, title: `Companion v${version}`, apk: `Companion-v${version}.apk`,
  };
}

function updatePubspec(text, release) {
  if (!/^version: \d+\.\d+\.\d+\+\d+\r?$/m.test(text)) {
    throw new Error('pubspec.yaml must contain version: X.Y.Z+N.');
  }
  return text.replace(/^version: [^\r\n]+/m, `version: ${release.versionName}+${release.versionCode}`);
}

function sourcePlan(context) {
  const run = context.payload.workflow_run;
  if (!run || run.repository?.full_name?.toLowerCase() !== `${context.repo.owner}/${context.repo.repo}`.toLowerCase()
      || run.path !== '.github/workflows/ci.yml' || run.conclusion !== 'success'
      || !['push', 'pull_request', 'workflow_dispatch'].includes(run.event)
      || (run.event !== 'pull_request' && run.head_branch !== 'main')
      || !/^[a-f0-9]{40}$/.test(run.head_sha)
      || !Number.isSafeInteger(run.id) || run.id < 1
      || !Number.isSafeInteger(run.run_attempt) || run.run_attempt < 1) {
    throw new Error('Refusing to publish an unexpected source workflow run.');
  }
  return {
    ...plan(run.run_number), sha: run.head_sha, prerelease: run.event === 'pull_request',
    artifact: `Companion-unsigned-${run.id}-${run.run_attempt}`,
  };
}

async function optional(request) {
  try { return (await request()).data; }
  catch (error) { if (error.status === 404) return null; throw error; }
}

async function existingRelease(github, repo, release) {
  const ref = await optional(() => github.rest.git.getRef({ ...repo, ref: `tags/${release.tag}` }));
  if (ref && (ref.object.type !== 'commit' || ref.object.sha !== release.sha)) {
    throw new Error(`Tag ${release.tag} belongs to another commit; it will never be moved.`);
  }
  let existing = await optional(() => github.rest.repos.getReleaseByTag({ ...repo, tag: release.tag }));
  // The tag endpoint only promises published releases; list drafts for recovery.
  if (!existing && ref) {
    const releases = await github.paginate(github.rest.repos.listReleases, { ...repo, per_page: 100 });
    existing = releases.find(item => item.tag_name === release.tag) || null;
  }
  if (existing && !ref) throw new Error('Release exists without the expected source tag.');
  return { ref, existing };
}

async function prepare({ github, context, core }) {
  const release = sourcePlan(context);
  const { existing } = await existingRelease(github, context.repo, release);
  for (const [name, value] of Object.entries(release)) core.setOutput(name, value);
  core.setOutput('skip', Boolean(existing && !existing.draft));
  if (existing && !existing.draft) core.notice(`${release.title} is already published. Keeping it unchanged.`);
}

function versionParts(tag) {
  const match = /^v(\d+)\.(\d+)$/.exec(tag);
  return match ? match.slice(1).map(Number) : null;
}

function compareVersions(left, right) {
  return left[0] - right[0] || left[1] - right[1];
}

async function changelog(github, context, release, releases) {
  const previous = releases.filter(item => !item.draft && !item.prerelease && versionParts(item.tag_name)
    && compareVersions(versionParts(item.tag_name), versionParts(release.tag)) < 0)
    .sort((a, b) => compareVersions(versionParts(b.tag_name), versionParts(a.tag_name)))[0];
  const base = release.prerelease ? context.payload.repository.default_branch : previous?.tag_name;
  const commits = [];
  for (let page = 1; ; page++) {
    const response = base
      ? await github.rest.repos.compareCommitsWithBasehead({
        ...context.repo, basehead: `${base}...${release.sha}`, per_page: 100, page,
      })
      : await github.rest.repos.listCommits({ ...context.repo, sha: release.sha, per_page: 100, page });
    const batch = base ? response.data.commits : response.data;
    commits.push(...batch);
    if (batch.length < 100) break;
  }
  if (!commits.length) {
    commits.push((await github.rest.repos.getCommit({ ...context.repo, ref: release.sha })).data);
  }
  const url = `https://github.com/${context.repo.owner}/${context.repo.repo}`;
  const lines = commits.map(commit => {
    const subject = commit.commit.message.split(/\r?\n/)[0]
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/[\\`*_[\]]/g, '\\$&');
    return `- ${subject} ([${commit.sha.slice(0, 7)}](${url}/commit/${commit.sha}))`;
  });
  return [
    `# ${release.title}`, '',
    release.prerelease ? 'Pull request preview build.' : 'Android release.', '',
    `Download \`${release.apk}\` for Android 7.0 (API 24) or newer.`,
    `App version: \`${release.versionName}+${release.versionCode}\`.`,
    `Source: [${release.sha.slice(0, 7)}](${url}/commit/${release.sha}).`, '',
    '## Changelog', '', ...lines, '',
  ].join('\n');
}

async function publish({ github, context, core, directory }) {
  const release = sourcePlan(context);
  const repo = context.repo;
  let { ref, existing } = await existingRelease(github, repo, release);
  if (existing && !existing.draft) {
    core.notice(`${release.title} is already published. Keeping it unchanged.`);
    return;
  }
  const releases = await github.paginate(github.rest.repos.listReleases, { ...repo, per_page: 100 });
  const body = existing?.body || await changelog(github, context, release, releases);
  fs.writeFileSync(path.join(directory, 'CHANGELOG.md'), body);
  const names = [release.apk, 'CHANGELOG.md'];
  const checksums = names.map(name => `${createHash('sha256').update(fs.readFileSync(path.join(directory, name))).digest('hex')}  ${name}\n`).join('');
  fs.writeFileSync(path.join(directory, 'SHA256SUMS.txt'), checksums);
  names.push('SHA256SUMS.txt');
  if (!ref) {
    await github.rest.git.createRef({ ...repo, ref: `refs/tags/${release.tag}`, sha: release.sha });
  }
  if (!existing) {
    existing = (await github.rest.repos.createRelease({
      ...repo, tag_name: release.tag, target_commitish: release.sha,
      name: release.title, body, draft: true, prerelease: release.prerelease,
    })).data;
  }
  for (const name of names) {
    const data = fs.readFileSync(path.join(directory, name));
    const asset = existing.assets.find(item => item.name === name);
    if (asset) {
      const digest = `sha256:${createHash('sha256').update(data).digest('hex')}`;
      if (asset.state !== 'uploaded' || asset.digest !== digest) {
        throw new Error(`Existing draft asset ${name} differs. Refusing to overwrite it.`);
      }
      continue;
    }
    await github.rest.repos.uploadReleaseAsset({
      ...repo, release_id: existing.id, name, data,
      headers: { 'content-type': name.endsWith('.apk') ? 'application/vnd.android.package-archive' : 'text/plain', 'content-length': data.length },
    });
  }
  const newerStable = releases.some(item => !item.draft && !item.prerelease && versionParts(item.tag_name)
    && compareVersions(versionParts(item.tag_name), versionParts(release.tag)) > 0);
  await github.rest.repos.updateRelease({
    ...repo, release_id: existing.id, draft: false,
    make_latest: release.prerelease || newerStable ? 'false' : 'true',
  });
  core.notice(`Published ${release.title} with its APK, changelog and checksums.`);
}

module.exports = { plan, updatePubspec, sourcePlan, prepare, changelog, publish };

if (require.main === module) {
  if (process.argv[2] !== 'plan') throw new Error('Usage: node scripts/release.cjs plan');
  const release = plan(process.env.GITHUB_RUN_NUMBER);
  fs.writeFileSync('pubspec.yaml', updatePubspec(fs.readFileSync('pubspec.yaml', 'utf8'), release));
  console.log(`${release.title} (${release.versionName}+${release.versionCode})`);
}
