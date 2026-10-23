"""Offline tests: python3 -m unittest discover -s scripts/tests -v.

Git/Go/curl/container APIs are mocked. These tests never download modules,
run a container, publish a release, or establish that D2 actually builds.
"""

import hashlib
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PREPARE = ROOT / "scripts/prepare-go-deps.sh"
UPGRADE = ROOT / "scripts/upgrade-ebuild.sh"
FINALIZER = ROOT / "scripts/agent-finalize-ebuild.sh"
VERSION = "0.9.0"
NAME = f"d2-{VERSION}-go-deps.tar.xz"
META_NAME = f"d2-{VERSION}-go-deps.json"
COMMIT = "a" * 40
MOD = "module github.com/d2lang/d2\n\ngo 1.27.0\n"
SUM = "example.org/module v1.0.0 h1:fixture\n"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def block(path, marker, after=None):
    """Extract an indented YAML literal block without a YAML dependency."""
    lines = path.read_text().splitlines()
    start = 0 if after is None else next(
        i for i, line in enumerate(lines) if line.strip() == after
    )
    index = next(
        i for i, line in enumerate(lines) if i >= start and line.strip() == marker
    )
    indent = len(lines[index]) - len(lines[index].lstrip())
    result = []
    for line in lines[index + 1 :]:
        if line.strip() and len(line) - len(line.lstrip()) <= indent:
            break
        result.append(line)
    return textwrap.dedent("\n".join(result))


class Fixture(unittest.TestCase):
    def setUp(self):
        # Scratch defaults to the repository, with an explicit override for the
        # designated maintainer workspace; never use the host /tmp default.
        self.tmp = tempfile.TemporaryDirectory(
            prefix=".go-deps-test-", dir=os.environ.get("GO_DEPS_TEST_TMPDIR", ROOT)
        )
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.output = self.base / "output"
        self.output.mkdir()
        self.log = self.base / "calls.jsonl"
        self.env = os.environ.copy()
        self.env.pop('GO_DEPS_RUNTIME', None)
        self.env.update(
            PATH=f"{self.bin}:{os.environ['PATH']}",
            TEST_LOG=str(self.log),
            TEST_MOD=MOD,
            TEST_SUM=SUM,
            TEST_COMMIT=COMMIT,
            ADAPTIVE_GO_DEPS_CONTAINER="1",
            GITHUB_REPOSITORY="Faraclas/adaptive-overlay",
        )

    def executable(self, name, code):
        path = self.bin / name
        path.write_text(f"#!{sys.executable}\n" + textwrap.dedent(code))
        path.chmod(0o755)

    def run_script(self, script, *args, ok=True):
        result = subprocess.run(
            ["bash", str(script), *args],
            cwd=ROOT,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
            timeout=30,
        )
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def calls(self):
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines()]


class GeneratorTests(Fixture):
    def setUp(self):
        super().setUp()
        self.executable(
            "git",
            r"""
            import json, os, pathlib, sys
            args = sys.argv[1:]
            with open(os.environ['TEST_LOG'], 'a') as log:
                log.write(json.dumps(['git'] + args) + '\n')
            if args[0] == 'init':
                source = pathlib.Path(args[-1])
                source.mkdir()
                (source / 'go.mod').write_text(os.environ['TEST_MOD'])
                (source / 'go.sum').write_text(os.environ['TEST_SUM'])
            elif args == ['rev-parse', 'HEAD']:
                print(os.environ['TEST_COMMIT'])
            elif args[0] == 'status':
                for name, key in [('go.mod', 'TEST_MOD'), ('go.sum', 'TEST_SUM')]:
                    if pathlib.Path(name).read_text() != os.environ[key]:
                        print(' M ' + name)
            elif args[:2] == ['--no-pager', 'diff']:
                import difflib
                for name, key in [('go.mod', 'TEST_MOD'), ('go.sum', 'TEST_SUM')]:
                    print(''.join(difflib.unified_diff(
                        os.environ[key].splitlines(keepends=True),
                        pathlib.Path(name).read_text().splitlines(keepends=True),
                        fromfile='a/' + name, tofile='b/' + name)), end='')
            """,
        )
        self.executable(
            "go",
            r"""
            import json, os, pathlib, sys
            args = sys.argv[1:]
            assert os.environ['GOTOOLCHAIN'] == 'local'
            assert os.environ['GOENV'] == 'off'
            assert os.environ['GOWORK'] == 'off'
            assert os.environ['GOFLAGS'] == ''
            assert os.environ['GOMODCACHE'].endswith('/go-mod')
            with open(os.environ['TEST_LOG'], 'a') as log:
                log.write(json.dumps(['go'] + args) + '\n')
            if os.environ.get('TEST_GO_FAIL') and args == ['mod', 'download', '-modcacherw']:
                sys.exit('go.mod requires go >= 1.27.0 (GOTOOLCHAIN=local)')
            if args == ['version']:
                print('go version go1.27.0 linux/amd64')
            elif args == ['mod', 'download', '-modcacherw']:
                assert os.environ['GOPROXY'] == 'https://proxy.golang.org'
                assert os.environ['GOSUMDB'] == 'sum.golang.org'
                root = pathlib.Path(os.environ['GOMODCACHE'])
                cached = root / 'cache/download/example.org/module/@v'
                cached.mkdir(parents=True)
                (cached / 'list').write_text(os.environ.get('TEST_LIST', 'v2\nv1\nv2\n'))
                (cached / 'v1.0.0.mod').write_text('module example.org/module\n')
                (cached / 'v1.0.0.lock').touch()
                sumdb = root / 'cache/download/sumdb'
                sumdb.mkdir()
                (sumdb / 'volatile').write_text(os.environ.get('TEST_LIST', 'default'))
                module = root / 'example.org/module@v1.0.0'
                module.mkdir(parents=True)
                (module / 'source.go').write_text('package module\n')
                (module / 'source').mkdir()
                (module / 'source/nested.go').write_text('package source\n')
                (module / 'LICENSE').write_text('fixture license\n')
                os.utime(module / 'source.go', (1234, int(os.environ.get('TEST_MTIME', '5678'))))
                if os.environ.get('TEST_DIRTY'):
                    with open('go.sum', 'a') as sums:
                        sums.write('unexpected.example/module v1.0.0 h1:unexpected\n')
            elif args in (['mod', 'verify'], ['list', '-mod=readonly', '-deps', '-test', './...']):
                assert os.environ['GOPROXY'] == 'off'
                assert os.environ['GOSUMDB'] == 'off'
                if os.environ.get('TEST_OFFLINE_FAIL') and args[0] == 'list':
                    sys.exit('module lookup disabled by GOPROXY=off')
                if os.environ.get('TEST_LIST_DIRTY') and args[0] == 'list':
                    with open('go.mod', 'a') as module:
                        module.write('// unexpected module edit\n')
            else:
                sys.exit('unexpected Go command: ' + repr(args))
            """,
        )

    def generate(self, output=None, ok=True):
        return self.run_script(
            PREPARE, "--in-container", "media-gfx/d2", "--version", VERSION,
            "--output", str(output or self.output), ok=ok,
        )

    def test_reproducible_cache_layout_and_provenance(self):
        self.generate()
        first = (self.output / NAME).read_bytes()
        metadata = json.loads((self.output / META_NAME).read_text())
        self.assertEqual(metadata['sha256'], sha(first))
        self.assertEqual(metadata['source_commit'], COMMIT)
        self.assertEqual(metadata['go_mod_sha256'], sha(MOD.encode()))
        self.assertEqual(metadata['go_sum_sha256'], sha(SUM.encode()))
        self.assertEqual(metadata['go_min_version'], '1.27.0')
        with tarfile.open(self.output / NAME) as archive:
            members = archive.getmembers()
            # GNU tar sorts each directory before recursively visiting it.
            # A global full-path sort instead puts source.go before source/x.
            names = [m.name for m in members]
            self.assertEqual(names, sorted(names, key=lambda name: name.split('/')))
            for member in members:
                self.assertTrue(member.name == 'go-mod' or member.name.startswith('go-mod/'))
                self.assertEqual((member.mtime, member.uid, member.gid), (0, 0, 0))
                self.assertFalse(member.name.startswith('go-mod/cache/download/sumdb'))
                self.assertFalse('/cache/download/' in member.name and member.name.endswith('.lock'))
            version_list = archive.extractfile('go-mod/cache/download/example.org/module/@v/list')
            assert version_list is not None
            self.assertEqual(version_list.read(), b'v1\nv2\n')
        second = self.base / 'second'
        second.mkdir()
        self.env.update(TEST_LIST='v1\nv2\n', TEST_MTIME='999999')
        self.generate(second)
        self.assertEqual(first, (second / NAME).read_bytes())
        self.assertEqual((self.output / META_NAME).read_bytes(), (second / META_NAME).read_bytes())
        self.assertIn(['go', 'mod', 'download', '-modcacherw'], self.calls())
        self.assertFalse(any(call[0] == 'go' and 'all' in call for call in self.calls()))
        fetches = [call for call in self.calls() if 'fetch' in call]
        self.assertTrue(all(call[-1] == 'refs/tags/v0.9.0' for call in fetches))
        self.assertFalse(list(self.output.glob('.go-deps.*')))

    def test_identical_rerun_and_mismatch_refusal(self):
        self.generate()
        self.generate()
        (self.output / NAME).write_bytes(b'existing immutable archive')
        result = self.generate(ok=False)
        self.assertIn('exists with different bytes', result.stderr)
        self.assertEqual((self.output / NAME).read_bytes(), b'existing immutable archive')

    def test_provenance_mismatch_refused_even_for_same_archive(self):
        self.generate()
        self.env['TEST_COMMIT'] = 'b' * 40
        result = self.generate(ok=False)
        self.assertIn(META_NAME, result.stderr)

    def test_toolchain_offline_and_source_mutation_fail_closed(self):
        for key in ('TEST_GO_FAIL', 'TEST_OFFLINE_FAIL', 'TEST_DIRTY', 'TEST_LIST_DIRTY'):
            with self.subTest(key=key):
                self.env[key] = '1'
                self.generate(ok=False)
                self.assertFalse((self.output / NAME).exists())
                self.assertFalse(list(self.output.glob('.go-deps.*')))
                del self.env[key]

    def test_download_mutation_reports_diff_and_stops_before_verification(self):
        self.env['TEST_DIRTY'] = '1'
        result = self.generate(ok=False)
        self.assertIn('after module download', result.stderr)
        self.assertIn('--- a/go.sum', result.stderr)
        self.assertIn('+unexpected.example/module v1.0.0 h1:unexpected', result.stderr)
        self.assertNotIn(['go', 'mod', 'verify'], self.calls())

    def test_offline_resolution_mutation_reports_diff(self):
        self.env['TEST_LIST_DIRTY'] = '1'
        result = self.generate(ok=False)
        self.assertIn('after offline root package/test resolution', result.stderr)
        self.assertIn('--- a/go.mod', result.stderr)
        self.assertIn('+// unexpected module edit', result.stderr)

    def test_private_entry_point_requires_wrapper_marker(self):
        del self.env['ADAPTIVE_GO_DEPS_CONTAINER']
        result = self.generate(ok=False)
        self.assertIn('use the container wrapper', result.stderr)
        self.assertFalse(self.calls())

    def test_explicit_runtime_uses_the_authenticated_image_store(self):
        self.executable('podman', "import sys; sys.exit('unexpected Podman execution')")
        self.executable(
            'docker',
            r"""
            import json, os, sys
            with open(os.environ['TEST_LOG'], 'a') as log:
                log.write(json.dumps(['docker'] + sys.argv[1:]) + '\n')
            """,
        )
        self.env['GO_DEPS_RUNTIME'] = 'docker'
        pinned = 'ghcr.io/faraclas/adaptive-overlay/testenv-rust@sha256:' + 'd' * 64
        self.run_script(PREPARE, 'media-gfx/d2', '--version', VERSION,
                        '--output', str(self.output), '--image', pinned)
        self.assertEqual(self.calls()[-1][0], 'docker')
        self.assertIn(pinned, self.calls()[-1])
        self.env['GO_DEPS_RUNTIME'] = 'sh'
        result = self.run_script(PREPARE, 'media-gfx/d2', '--version', VERSION,
                                 '--output', str(self.output), ok=False)
        self.assertIn('GO_DEPS_RUNTIME must be podman or docker', result.stderr)

    def test_wrapper_runtime_image_and_mount_contract(self):
        self.executable(
            'podman',
            r"""
            import json, os, sys
            args = sys.argv[1:]
            with open(os.environ['TEST_LOG'], 'a') as log:
                log.write(json.dumps(['podman'] + args) + '\n')
            if args[:2] == ['image', 'inspect']:
                sys.exit(int(os.environ.get('TEST_IMAGE_MISSING', '0')))
            """,
        )
        for missing, image in (
            ('0', 'localhost/adaptive-overlay-testenv-rust:local'),
            ('1', 'ghcr.io/faraclas/adaptive-overlay/testenv-rust:latest'),
        ):
            with self.subTest(image=image):
                self.env['TEST_IMAGE_MISSING'] = missing
                self.run_script(PREPARE, 'media-gfx/d2', '--version', VERSION,
                                '--output', str(self.output))
                run = self.calls()[-1]
                self.assertIn(image, run)
                self.assertIn(f'{ROOT}:/overlay:ro', run)
                self.assertIn(f'{self.output}:/output', run)
                self.assertIn('--user', run)
                if os.geteuid() != 0:
                    self.assertIn('--userns=keep-id', run)
                self.assertIn('ADAPTIVE_GO_DEPS_CONTAINER=1', run)
                self.assertIn('--in-container', run)
        result = self.run_script(PREPARE, 'media-gfx/d2', '--version', VERSION,
                                 '--output', '/etc/d2-deps-forbidden', ok=False)
        self.assertIn('output must be inside', result.stderr)
        self.run_script(PREPARE, 'media-gfx/d2', '--version', '../main',
                        '--output', str(self.output), ok=False)


class UpgradeTests(Fixture):
    def setUp(self):
        super().setUp()
        self.overlay = self.base / 'overlay'
        for directory in ('metadata', '.agent', 'media-gfx/d2', 'scripts'):
            (self.overlay / directory).mkdir(parents=True, exist_ok=True)
        (self.overlay / 'metadata/layout.conf').touch()
        (self.overlay / '.agent/packages.json').write_text(json.dumps([{
            'category': 'media-gfx', 'name': 'd2', 'build_system': 'go',
            'upstream_repo': 'd2lang/d2', 'upstream_type': 'github-release',
            'version_pattern': 'v(.*)',
        }]))
        self.package = self.overlay / 'media-gfx/d2'
        (self.package / 'd2-0.8.0.ebuild').write_text('EAPI=8\ninherit go-module\n')
        manifest = self.overlay / 'scripts/manifest.sh'
        manifest.write_text('#!/bin/bash\necho manifest-called >> "${TEST_LOG}"\n')
        manifest.chmod(0o755)
        self.env['OVERLAY_DIR'] = str(self.overlay)
        self.executable(
            'curl',
            r"""
            import hashlib, json, os, sys
            args = sys.argv[1:]
            url = args[-1]
            with open(os.environ['TEST_LOG'], 'a') as log:
                log.write(json.dumps(['curl', url]) + '\n')
            def sha(value):
                return hashlib.sha256(value.encode()).hexdigest()
            if any('I' in arg for arg in args if arg.startswith('-')):
                if 'go-deps.tar.xz' in url and os.environ.get('TEST_MISSING'):
                    sys.exit(22)
                sys.exit(0)
            if url.endswith('go-deps.json'):
                meta = dict(schema=1, upstream='d2lang/d2', tag='v0.9.0',
                            archive='d2-0.9.0-go-deps.tar.xz', sha256='c' * 64,
                            source_commit=os.environ['TEST_COMMIT'], go_min_version='1.27.0',
                            go_mod_sha256=sha(os.environ['TEST_MOD']),
                            go_sum_sha256=sha(os.environ['TEST_SUM']))
                if os.environ.get('TEST_BAD_PROVENANCE'):
                    meta['source_commit'] = 'b' * 40
                print(json.dumps(meta))
            elif '/commits/v' in url:
                print(json.dumps(dict(sha=os.environ['TEST_COMMIT'])))
            elif url.endswith('go.mod'):
                content = os.environ['TEST_MOD']
                if '/v0.8.0/' in url:
                    content = content.replace('1.27.0', '1.26.0')
                print(content, end='')
            elif url.endswith('go.sum'):
                print(os.environ['TEST_SUM'], end='')
            elif '/releases?' in url:
                print('[{"tag_name":"v0.9.0","draft":false,"prerelease":false}]')
            else:
                sys.exit('unexpected URL: ' + url)
            """,
        )

    def upgrade(self, *args, ok=True):
        return self.run_script(UPGRADE, 'media-gfx/d2', '--version', VERSION,
                               '--json', *args, ok=ok)

    def test_plan_is_read_only_and_does_not_check_sources(self):
        result = json.loads(self.upgrade('--check').stdout)
        self.assertEqual(result['status'], 'upgrade-available')
        self.assertFalse(result['sources_checked'])
        self.assertFalse(self.calls())
        self.assertFalse((self.package / 'd2-0.9.0.ebuild').exists())
        self.upgrade('--check', '--apply', ok=False)

    def test_missing_archive_blocks_copy_and_manifest(self):
        self.env['TEST_MISSING'] = '1'
        result = self.upgrade('--manifest', ok=False)
        self.assertIn('not published', result.stderr)
        self.assertFalse((self.package / 'd2-0.9.0.ebuild').exists())
        self.assertNotIn('manifest-called', self.log.read_text())

    def test_provenance_mismatch_blocks_copy(self):
        self.env['TEST_BAD_PROVENANCE'] = '1'
        result = self.upgrade('--apply', ok=False)
        self.assertIn('does not match the exact source release', result.stderr)
        self.assertFalse((self.package / 'd2-0.9.0.ebuild').exists())

    def test_ready_archive_reports_go_review_requirements(self):
        result = json.loads(self.upgrade('--apply').stdout)
        self.assertEqual(result['status'], 'upgrade-prepared')
        self.assertEqual(result['go_min_ver'], '1.27.0')
        self.assertTrue(result['go_modules_changed'])
        self.assertTrue(result['go_deps']['ready'])
        self.assertTrue(result['go_deps']['url'].endswith(f'/d2-deps-{VERSION}/{NAME}'))
        self.assertEqual(result['go_deps']['source_commit'], COMMIT)
        self.assertTrue((self.package / 'd2-0.9.0.ebuild').exists())

    def test_exact_module_bytes_preserved_for_provenance(self):
        for mod in (MOD.rstrip('\n'), MOD + '\n'):
            with self.subTest(mod=repr(mod)):
                self.env['TEST_MOD'] = mod
                result = json.loads(self.upgrade('--check').stdout)
                self.assertEqual(result['status'], 'upgrade-available')
                # Use a fresh version-copy path for each normal preparation.
                copied = self.package / 'd2-0.9.0.ebuild'
                copied.unlink(missing_ok=True)
                result = json.loads(self.upgrade('--apply').stdout)
                self.assertEqual(result['go_deps']['go_mod_sha256'], sha(mod.encode()))
                copied.unlink()

    def test_non_go_path_does_not_require_archive(self):
        registry = self.overlay / '.agent/packages.json'
        data = json.loads(registry.read_text())
        data[0]['build_system'] = 'make'
        registry.write_text(json.dumps(data))
        self.env['TEST_MISSING'] = '1'
        result = json.loads(self.upgrade('--apply').stdout)
        self.assertEqual(result['status'], 'upgrade-prepared')
        self.assertIsNone(result['go_deps'])
        self.assertFalse(any('go-deps' in call[-1] for call in self.calls()))


class PublicationTests(Fixture):
    def test_publication_lifecycle_with_mock_github_api(self):
        # Run the actual workflow JavaScript, replacing only GitHub API calls.
        script = block(
            ROOT / '.github/workflows/prepare-go-deps.yml', 'script: |',
            after='- name: Publish or verify immutable release assets',
        )
        work = self.base / '.go-deps-output'
        work.mkdir()
        (work / NAME).write_bytes(b'archive fixture')
        (work / META_NAME).write_text(json.dumps({
            'tag': 'v0.9.0', 'archive': NAME, 'upstream': 'd2lang/d2',
            'sha256': sha(b'archive fixture'), 'source_commit': COMMIT,
        }))
        harness = self.base / 'publication.cjs'
        harness.write_text(textwrap.dedent("""
            const fs = require('fs');
            const path = require('path');
            const assert = require('assert/strict');
            const source = process.argv[2];
            const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
            const publish = new AsyncFunction('require', 'github', 'context', 'core', source);
            const names = ['d2-0.9.0-go-deps.tar.xz', 'd2-0.9.0-go-deps.json'];
            async function scenario(mode) {
              const calls = [];
              const existing = !['new', 'draft-partial'].includes(mode);
              const draft = mode.startsWith('draft');
              const repos = {
                getReleaseByTag: async () => {
                  if (['new', 'draft-partial'].includes(mode)) throw Object.assign(new Error('not found'), {status: 404});
                  if (mode === 'api-error') throw Object.assign(new Error('API denied'), {status: 403});
                  return {data: {id: 1, draft}};
                },
                createRelease: async args => {
                  assert.equal(args.draft, true);
                  calls.push('create');
                  return {data: {id: 1, draft: true}};
                },
                listReleases: 'releases',
                listReleaseAssets: 'list',
                getReleaseAsset: async args => {
                  calls.push('verify');
                  let data = fs.readFileSync(path.join(process.env.GITHUB_WORKSPACE,
                    '.go-deps-output', names[args.asset_id]));
                  if (mode === 'mismatch' || (mode === 'metadata-mismatch' && args.asset_id === 1)) {
                    data = Buffer.from('different immutable bytes');
                  }
                  return {data};
                },
                uploadReleaseAsset: async args => { calls.push('upload:' + args.name); },
                updateRelease: async args => {
                  assert.equal(args.draft, false);
                  assert.equal(args.make_latest, 'false');
                  calls.push('publish');
                }
              };
              const github = {
                rest: {repos},
                paginate: async endpoint => {
                  if (endpoint === 'releases') {
                    return mode === 'draft-partial' ? [{id: 1, draft: true, tag_name: 'd2-deps-0.9.0'}] : [];
                  }
                  return names.flatMap((name, id) => {
                  if (mode === 'draft-partial' && id === 0) return [{name, id}];
                  if (mode === 'published-missing' && id === 1) return [];
                  return existing ? [{name, id}] : [];
                  });
                }
              };
              const outputs = {};
              const core = {setOutput: (k, v) => outputs[k] = v, notice: () => {}};
              const context = {repo: {owner: 'Faraclas', repo: 'adaptive-overlay'}, sha: 'fixture'};
              let error;
              try { await publish(require, github, context, core); } catch (e) { error = e; }
              if (['mismatch', 'metadata-mismatch', 'published-missing', 'api-error'].includes(mode)) {
                assert.ok(error, mode + ' must fail');
                assert.ok(!calls.some(c => c.startsWith('upload') || c === 'publish' || c === 'create'));
                assert.equal(outputs.archive_url, undefined);
              } else {
                if (error) throw error;
                assert.ok(outputs.archive_url.endsWith('/d2-deps-0.9.0/' + names[0]));
                if (mode === 'new') assert.deepEqual(calls, ['create', ...names.map(n => 'upload:' + n), 'publish']);
                if (mode === 'matching') assert.deepEqual(calls, ['verify', 'verify']);
                if (mode === 'draft-partial') assert.deepEqual(calls, ['verify', 'upload:' + names[1], 'publish']);
              }
            }
            (async () => {
              for (const mode of ['new', 'matching', 'mismatch', 'metadata-mismatch',
                                  'published-missing', 'draft-partial', 'api-error']) {
                await scenario(mode);
              }
            })().catch(error => { console.error(error); process.exit(1); });
        """))
        result = subprocess.run(
            ['node', str(harness), script], env={**self.env, 'VERSION': VERSION,
            'GITHUB_WORKSPACE': str(self.base)}, text=True, capture_output=True, check=False, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_upgrade_workflow_go_only_ordering_and_required_skills(self):
        workflow = (ROOT / '.github/workflows/upgrade-ebuild.yml').read_text()
        self.assertIn("needs.plan.outputs.build_system == 'go'", workflow)
        self.assertIn('needs: [plan, prepare-go-deps]', workflow)
        self.assertIn("needs.prepare-go-deps.result == 'success'", workflow)
        self.assertIn("needs.prepare-go-deps.result == 'skipped'", workflow)
        self.assertIn('VERSION: ${{ needs.plan.outputs.version }}', workflow)
        self.assertIn('needs: detect', workflow)
        self.assertIn("needs.detect.result == 'success'", workflow)
        self.assertIn('.agent/skills/update-d2.md', workflow)
        self.assertIn('.agent/skills/update-d2-mcp.md', workflow)
        self.assertIn('Required package upgrade instructions missing', workflow)
        self.assertIn('Required shared finalization instructions missing', workflow)
        self.assertIn('finalizer_file=${FINALIZER_FILE}', workflow)
        self.assertIn('Read shared finalization instructions', workflow)
        scheduled = (ROOT / '.github/workflows/ci-version-check.yml').read_text()
        caller = scheduled.split('  upgrade:\n', 1)[1]
        for permission in ('contents: write', 'packages: read', 'issues: write'):
            self.assertIn(permission, caller)


class LocalFinalizerTests(Fixture):
    def setUp(self):
        super().setUp()
        self.overlay = self.base / 'overlay'
        for directory in ('metadata', 'scripts', '.agent/skills'):
            (self.overlay / directory).mkdir(parents=True, exist_ok=True)
        (self.overlay / 'metadata/layout.conf').touch()
        self.env['OVERLAY_DIR'] = str(self.overlay)
        self.ebuilds = {}
        for package in ('media-gfx/d2', 'media-gfx/d2-mcp', 'app-editors/zed'):
            directory = self.overlay / package
            directory.mkdir(parents=True)
            ebuild = directory / f'{package.split("/")[-1]}-{VERSION}.ebuild'
            ebuild.write_text('EAPI=8\nDESCRIPTION="unchanged fixture"\n')
            self.ebuilds[package] = ebuild
        (self.overlay / '.agent/skills/update-zed-editor.md').write_text(
            '# Fixture Zed procedure\n'
        )
        (self.overlay / 'scripts/upgrade-ebuild.sh').write_text(
            '#!/bin/bash\n'
            'printf \'%s\\n\' \'["upgrade"]\' >> "${TEST_LOG}"\n'
            'printf \'%s\\n\' "${TEST_UPGRADE_REPORT}"\n'
        )
        self.executable(
            'copilot',
            r"""
            import json, os, sys
            with open(os.environ['TEST_LOG'], 'a') as log:
                log.write(json.dumps(['copilot'] + sys.argv[1:]) + '\n')
            sys.exit('unexpected live agent invocation in an offline test')
            """,
        )
        self.env['TEST_UPGRADE_REPORT'] = json.dumps(self.report('app-editors/zed'))

    def report(self, package, status='upgrade-prepared'):
        return {
            'status': status, 'package': package,
            'ebuild_path': str(self.ebuilds[package]), 'upstream': VERSION,
            'current': '0.8.0', 'rust_min_ver': None,
            'git_crates': {'added': [], 'removed': [], 'updated': []},
        }

    def assert_ebuilds_unchanged(self):
        for ebuild in self.ebuilds.values():
            self.assertEqual(ebuild.read_text(), 'EAPI=8\nDESCRIPTION="unchanged fixture"\n')

    def assert_guard(self, package, *args):
        result = self.run_script(FINALIZER, *args, ok=False)
        self.assertIn('requires multi-file finalization', result.stderr)
        self.assertIn('.agent/skills/finalize-upgrade.md', result.stderr)
        self.assertIn(f'.agent/skills/update-{package.split("/")[-1]}.md', result.stderr)
        if package == 'media-gfx/d2':
            self.assertIn('scripts/prepare-go-deps.sh media-gfx/d2', result.stderr)
            self.assertIn('Local generation does not publish', result.stderr)
        self.assertNotIn('DRY RUN', result.stdout)
        self.assertFalse(self.calls(), result.stdout + result.stderr)
        self.assert_ebuilds_unchanged()

    def test_d2_and_mcp_direct_invocation_rejected_before_upgrade_or_agent(self):
        for package in ('media-gfx/d2', 'media-gfx/d2-mcp'):
            for options in ((), ('--dry-run',)):
                with self.subTest(package=package, options=options):
                    self.assert_guard(package, package, '--version', VERSION, *options)

    def test_d2_and_mcp_json_reports_rejected_before_ebuild_resolution(self):
        report = self.base / 'upgrade.json'
        for package in ('media-gfx/d2', 'media-gfx/d2-mcp'):
            for status in ('upgrade-prepared', 'up-to-date'):
                for options in ((), ('--dry-run',)):
                    with self.subTest(package=package, status=status, options=options):
                        data = self.report(package, status)
                        data['ebuild_path'] = str(self.base / 'nonexistent.ebuild')
                        report.write_text(json.dumps(data))
                        self.assert_guard(package, '--json', str(report), *options)

    def test_duplicate_package_separator_cannot_bypass_guard(self):
        report = self.base / 'duplicate-separator.json'
        for package in ('media-gfx/d2', 'media-gfx/d2-mcp'):
            alias = package.replace('/', '//')
            with self.subTest(package=alias):
                self.assert_guard(package, alias, '--dry-run')
                data = self.report(package)
                data['package'] = alias
                report.write_text(json.dumps(data))
                self.assert_guard(package, '--json', str(report), '--dry-run')

    def test_zed_json_dry_run_still_loads_skill_and_does_not_edit(self):
        report = self.base / 'zed.json'
        report.write_text(json.dumps(self.report('app-editors/zed')))
        result = self.run_script(FINALIZER, '--json', str(report), '--dry-run')
        self.assertIn('DRY RUN', result.stdout)
        self.assertIn('Fixture Zed procedure', result.stdout)
        self.assertIn('Current Ebuild Content', result.stdout)
        self.assertFalse(self.calls())
        self.assert_ebuilds_unchanged()

    def test_zed_direct_dry_run_still_prepares_upgrade_without_agent(self):
        result = self.run_script(FINALIZER, 'app-editors/zed', '--dry-run')
        self.assertIn('DRY RUN', result.stdout)
        self.assertIn('Fixture Zed procedure', result.stdout)
        self.assertEqual(self.calls(), [['upgrade']])
        self.assert_ebuilds_unchanged()

    def test_zed_up_to_date_report_still_exits_successfully(self):
        report = self.base / 'zed-current.json'
        report.write_text(json.dumps(self.report('app-editors/zed', 'up-to-date')))
        result = self.run_script(FINALIZER, '--json', str(report), '--dry-run')
        self.assertIn('already up to date', result.stdout)
        self.assertNotIn('DRY RUN', result.stdout)
        self.assertFalse(self.calls())
        self.assert_ebuilds_unchanged()


class HostedReadinessTests(Fixture):
    def test_published_image_is_pinned_and_missing_provenance_fails_closed(self):
        script = block(
            ROOT / '.github/workflows/prepare-go-deps.yml', 'run: |',
            after='- name: Pull and pin the published headless Rust image',
        )
        self.executable(
            'docker',
            r"""
            import json, os, sys
            args = sys.argv[1:]
            with open(os.environ['TEST_LOG'], 'a') as log:
                log.write(json.dumps(['docker'] + args) + '\n')
            if args[0] == 'pull':
                sys.exit(int(os.environ.get('TEST_PULL_FAIL', '0')))
            if 'Labels' in args[3]:
                print(os.environ['TEST_REVISION'])
            else:
                print(os.environ['TEST_DIGEST'])
            """,
        )
        output = self.base / 'image-output'
        image = 'ghcr.io/faraclas/adaptive-overlay/testenv-rust@sha256:' + 'd' * 64
        for mode in ('ready', 'missing-label', 'bad-digest', 'pull-failure'):
            with self.subTest(mode=mode):
                output.write_text('')
                env = {**self.env, 'GITHUB_OUTPUT': str(output),
                       'TEST_REVISION': COMMIT if mode != 'missing-label' else '<no value>',
                       'TEST_DIGEST': image if mode != 'bad-digest' else 'mutable:latest',
                       'TEST_PULL_FAIL': '1' if mode == 'pull-failure' else '0'}
                result = subprocess.run(['bash'], input=script, env=env, text=True,
                                        capture_output=True, check=False, timeout=30)
                self.assertEqual(result.returncode == 0, mode == 'ready', result.stderr)
                if mode == 'ready':
                    self.assertIn('image=' + image, output.read_text())
                    self.assertIn('revision=' + COMMIT, output.read_text())
                else:
                    self.assertEqual(output.read_text(), '')
        workflow = (ROOT / '.github/workflows/prepare-go-deps.yml').read_text()
        steps = ['Pull and pin the published headless Rust image',
                 'Require publication of the current Go container layer',
                 'Generate and verify dependency sources in the headless Rust image',
                 'Publish or verify immutable release assets']
        self.assertEqual([workflow.index(step) for step in steps],
                         sorted(workflow.index(step) for step in steps))
        self.assertIn('GO_DEPS_RUNTIME: docker', workflow)
        self.assertIn('GO_DEPS_IMAGE: ${{ steps.image.outputs.image }}', workflow)

    def test_container_layer_gate_rejects_stale_or_unavailable_source(self):
        script = block(
            ROOT / '.github/workflows/prepare-go-deps.yml', 'script: |',
            after='- name: Require publication of the current Go container layer',
        )
        harness = self.base / 'image-gate.cjs'
        harness.write_text(textwrap.dedent("""
            const fs = require('fs');
            const assert = require('assert/strict');
            const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
            const gate = new AsyncFunction('require', 'github', 'core', process.argv[2]);
            (async () => {
              for (const mode of ['ready', 'stale', 'not-file', 'api-error']) {
                let notices = 0;
                const github = {rest: {repos: {getContent: async args => {
                  assert.equal(args.ref, process.env.IMAGE_REVISION);
                  assert.equal(args.owner, 'Faraclas');
                  assert.equal(args.repo, 'adaptive-overlay');
                  if (mode === 'api-error') throw Object.assign(new Error('denied'), {status: 403});
                  const current = fs.readFileSync(args.path);
                  const data = mode === 'stale' ? Buffer.from('old Go container layer') : current;
                  return {data: {type: mode === 'not-file' ? 'dir' : 'file',
                    encoding: 'base64', content: data.toString('base64')}};
                }}}};
                let error;
                try { await gate(require, github, {notice: () => notices++}); }
                catch (e) { error = e; }
                if (mode === 'ready') { if (error) throw error; assert.equal(notices, 1); }
                else { assert.ok(error, mode + ' must fail'); assert.equal(notices, 0); }
              }
            })().catch(error => { console.error(error); process.exit(1); });
        """))
        result = subprocess.run(
            ['node', str(harness), script], cwd=ROOT,
            env={**self.env, 'IMAGE_REVISION': COMMIT}, text=True,
            capture_output=True, check=False, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_handoff_requires_shared_and_correct_package_skills(self):
        workflow = ROOT / '.github/workflows/upgrade-ebuild.yml'
        script = block(workflow, 'run: |', after='- name: Build skills reference')
        directory = self.base / 'handoff'
        skills = directory / '.agent/skills'
        skills.mkdir(parents=True)
        shared = skills / 'finalize-upgrade.md'
        shared.write_text('# Shared finalization\n')
        output = self.base / 'skill-output'
        for package in ('d2', 'd2-mcp'):
            package_skill = skills / f'update-{package}.md'
            package_skill.write_text('# Package procedure\n')
            resolved = script.replace('${{ needs.detect.outputs.package }}', f'media-gfx/{package}')
            env = {**self.env, 'GITHUB_OUTPUT': str(output)}
            output.write_text('')
            result = subprocess.run(['bash'], input=resolved, cwd=directory, env=env,
                                    text=True, capture_output=True, check=False, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(f'skills_file=.agent/skills/update-{package}.md', output.read_text())
            self.assertIn('finalizer_file=.agent/skills/finalize-upgrade.md', output.read_text())
            package_skill.unlink()
            result = subprocess.run(['bash'], input=resolved, cwd=directory, env=env,
                                    text=True, capture_output=True, check=False, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Required package upgrade instructions missing', result.stdout)
        shared.unlink()
        result = subprocess.run(['bash'], input=resolved, cwd=directory, env=env,
                                text=True, capture_output=True, check=False, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Required shared finalization instructions missing', result.stdout)

    def test_summary_reports_preparation_failure_and_non_go_success(self):
        script = block(ROOT / '.github/workflows/upgrade-ebuild.yml', 'run: |',
                       after='- name: Write summary')
        output = self.base / 'summary'
        env = {**self.env, 'GITHUB_STEP_SUMMARY': str(output), 'PACKAGE': 'media-gfx/d2',
               'VERSION': VERSION, 'CURRENT': '0.8.0', 'STATUS': 'upgrade-prepared',
               'PLAN_RESULT': 'success', 'GO_DEPS_RESULT': 'success',
               'DETECT_RESULT': 'success', 'DELEGATE_RESULT': 'success', 'ISSUE_URL': ''}
        for key, value, message in (
            ('PLAN_RESULT', 'failure', 'Target resolution failed'),
            ('GO_DEPS_RESULT', 'failure', 'Required Go archive preparation/publication failed'),
            ('DETECT_RESULT', 'failure', 'Strict upgrade/source-readiness checks failed'),
            ('GO_DEPS_RESULT', 'skipped', 'Issue created and assigned to Copilot'),
        ):
            with self.subTest(key=key, value=value):
                output.write_text('')
                result = subprocess.run(['bash'], input=script, env={**env, key: value},
                                        text=True, capture_output=True, check=False, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(message, output.read_text())


if __name__ == '__main__':
    unittest.main()
