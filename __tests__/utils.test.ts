import {execFileSync} from 'node:child_process';
import {mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import * as utils from '../src/utils.js';

function getCacheScope(
  runner: string,
  shareAcrossJobs: string,
  shareAcrossWorkflows: string
): string {
  const command = `
    uname() { echo Windows; }
    export -f uname
    runner="$4" GITHUB_REPOSITORY=owner/repo GITHUB_WORKFLOW=ci GITHUB_JOB=test \\
      bash "$1" get_cache_scope "" "" "" "$2" "$3"
  `;

  return execFileSync(
    'bash',
    [
      '-c',
      command,
      'bash',
      utils.SCRIPT_PATH,
      shareAcrossJobs,
      shareAcrossWorkflows,
      runner
    ],
    {encoding: 'utf8'}
  ).trim();
}

describe('Utils tests', () => {
  let runnerTemp: string;

  beforeEach(() => {
    runnerTemp = mkdtempSync(join(tmpdir(), 'cache-extensions-utils-'));
    process.env['RUNNER_TEMP'] = runnerTemp;
  });

  afterEach(() => {
    rmSync(runnerTemp, {recursive: true, force: true});
  });

  it('checking getOutput', async () => {
    const file_path: string = join(runnerTemp, 'test');
    writeFileSync(file_path, 'test');
    expect(await utils.getOutput('test')).toBe('test');
  });

  it('checking filterExtensions', async () => {
    expect(utils.filterExtensions('a,:b,c')).toBe('a,c');
    expect(utils.filterExtensions('a, :b, c')).toBe('a, c');
  });

  it('checking SCRIPT_PATH', () => {
    expect(utils.SCRIPT_PATH).toBe(
      join(import.meta.dirname, '../src/scripts/cache.sh')
    );
  });

  it('checking scriptCall', () => {
    expect(utils.scriptCall('test', 'a', 'b')).toEqual({
      command: 'bash',
      args: [utils.SCRIPT_PATH, 'test', 'a', 'b']
    });
  });

  it.each([
    ['github', 'false', 'false', 'owner/repo-ci-test'],
    ['github', 'true', 'false', 'owner/repo-ci'],
    ['github', 'false', 'true', 'owner/repo-test'],
    ['github', 'true', 'true', 'owner/repo'],
    ['self-hosted', 'false', 'false', 'owner/repo-ci'],
    ['self-hosted', 'false', 'true', 'owner/repo']
  ])(
    'builds the cache scope for %s with job sharing %s and workflow sharing %s',
    (runner, shareAcrossJobs, shareAcrossWorkflows, expected) => {
      expect(getCacheScope(runner, shareAcrossJobs, shareAcrossWorkflows)).toBe(
        expected
      );
    }
  );
});
