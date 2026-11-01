"""初回Homebrew導入の制御テスト。公式インストーラーやbrewを実際には実行しない。"""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HomebrewTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='opencae-brew-')
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name).resolve() / '日本語 project'
        (self.path / 'setup/config').mkdir(parents=True)
        (self.path / 'scratch').mkdir()
        (self.path / 'home').mkdir()
        self.installer = self.path / 'installer.sh'
        self.installer.write_text('''#!/bin/bash
printf '%s|%s|%s' "${CI-unset}" "${NONINTERACTIVE-unset}" "${INTERACTIVE-unset}" > "$TEST_ROOT/executed"
[[ "${TEST_INSTALL_EXIT:-0}" == 0 ]] || exit "$TEST_INSTALL_EXIT"
[[ "${TEST_NO_BREW:-0}" == 1 ]] || touch "$TEST_ROOT/ready"
''')
        digest = hashlib.sha256(self.installer.read_bytes()).hexdigest()
        self.config = self.path / 'setup/config/homebrew.env'
        self.config.write_text('HOMEBREW_INSTALLER_URL=https://raw.githubusercontent.com/Homebrew/install/' + 'a' * 40 + '/install.sh\nHOMEBREW_INSTALLER_SHA256=' + digest + '\n')
        self.env = dict(os.environ, TEST_ROOT=str(self.path), HOME=str(self.path / 'home'),
                        TMPDIR=str(self.path / 'scratch'), TEST_TTY='yes')

    def run_bootstrap(self, **extra):
        env = dict(self.env, **extra)
        return subprocess.run(['/bin/bash', '-c', r'''
set -euo pipefail
source "$1/setup/macos/lib.sh"
source "$1/setup/macos/homebrew.sh"
MAC_ROOT="$TEST_ROOT"
mac_homebrew_available() { [[ -f "$TEST_ROOT/ready" ]]; }
mac_homebrew_terminal() { [[ "$TEST_TTY" == yes ]]; }
mac_homebrew() {
    printf '%s\n' "$*" >> "$TEST_ROOT/brew-calls"
    case "$1" in
        --prefix) printf '%s\n' "${TEST_PREFIX:-/opt/homebrew}" ;;
        --version) echo 'Homebrew test fixture' ;;
        *) exit 99 ;;
    esac
}
curl() {
    printf '%s\n' "$*" >> "$TEST_ROOT/curl-calls"
    [[ "${TEST_CURL_EXIT:-0}" == 0 ]] || return "$TEST_CURL_EXIT"
    while (( $# )); do
        if [[ "$1" == -o ]]; then cp "$TEST_ROOT/installer.sh" "$2"; return; fi
        shift
    done
    return 98
}
mac_bootstrap_homebrew
''', 'homebrew-test', str(ROOT)], env=env, text=True, capture_output=True)

    def assert_clean_scratch(self):
        self.assertEqual(list((self.path / 'scratch').iterdir()), [])

    def test_existing_homebrew_is_verified_without_download_or_terminal(self):
        (self.path / 'ready').touch()
        result = self.run_bootstrap(TEST_TTY='no')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.path / 'brew-calls').read_text().splitlines(), ['--prefix', '--version'])
        self.assertFalse((self.path / 'curl-calls').exists())
        self.assertFalse((self.path / 'executed').exists())

    def test_wrong_prefix_does_not_reinstall_or_continue(self):
        (self.path / 'ready').touch()
        result = self.run_bootstrap(TEST_PREFIX='/usr/local')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.path / 'curl-calls').exists())
        self.assertNotIn('--version', (self.path / 'brew-calls').read_text())

    def test_missing_homebrew_runs_verified_installer_interactively_and_can_repeat(self):
        result = self.run_bootstrap(CI='1', NONINTERACTIVE='1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.path / 'executed').read_text(), 'unset|unset|1')
        self.assertTrue((self.path / 'ready').exists())
        self.assert_clean_scratch()
        calls = (self.path / 'curl-calls').read_text()
        result = self.run_bootstrap(TEST_TTY='no')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.path / 'curl-calls').read_text(), calls)

    def test_missing_homebrew_without_terminal_stops_before_download(self):
        result = self.run_bootstrap(TEST_TTY='no')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('対話端末', result.stderr)
        self.assertFalse((self.path / 'curl-calls').exists())
        self.assertFalse((self.path / 'executed').exists())
        self.assert_clean_scratch()

    def test_download_failure_never_executes_and_cleans_temporary_directory(self):
        result = self.run_bootstrap(TEST_CURL_EXIT='22')
        self.assertEqual(result.returncode, 22)
        self.assertFalse((self.path / 'executed').exists())
        self.assert_clean_scratch()

    def test_hash_mismatch_never_executes_and_cleans_temporary_directory(self):
        self.config.write_text(self.config.read_text().replace(hashlib.sha256(self.installer.read_bytes()).hexdigest(), '0' * 64))
        result = self.run_bootstrap()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('SHA256', result.stderr)
        self.assertFalse((self.path / 'executed').exists())
        self.assert_clean_scratch()

    def test_install_failure_preserves_exit_and_can_retry(self):
        result = self.run_bootstrap(TEST_INSTALL_EXIT='17')
        self.assertEqual(result.returncode, 17)
        self.assertIn('再実行', result.stderr)
        self.assertFalse((self.path / 'ready').exists())
        self.assert_clean_scratch()
        self.assertEqual(self.run_bootstrap().returncode, 0)

    def test_success_without_native_brew_is_rejected(self):
        result = self.run_bootstrap(TEST_NO_BREW='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('確認できません', result.stderr)
        self.assert_clean_scratch()


if __name__ == '__main__':
    unittest.main()
