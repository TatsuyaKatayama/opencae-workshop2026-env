"""Guard CI coverage and prevent duplicate CFD builds across platform changes."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('changes', Path(__file__).resolve().parents[1] / 'scripts/ci/changes.py')
changes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(changes)


class CoverageTests(unittest.TestCase):
    def test_docs_do_not_install_platforms(self):
        self.assertFalse(any(changes.select(['README.md', 'docs/macos.md']).values()))

    def test_windows_edit_reaches_actual_wsl(self):
        result = changes.select(['setup/windows/Common.ps1'])
        self.assertTrue(result['windows'] and result['wsl'])
        self.assertFalse(result['macos'] or result['image'] or result['setup'])

    def test_mac_edit_does_not_rebuild_linux_cfd(self):
        result = changes.select(['setup/macos/control.py'])
        self.assertTrue(result['macos'] and result['macos_vm'])
        self.assertFalse(result['backends'] or result['windows'] or result['image'] or result['setup'])

    def test_shared_engine_change_reaches_mac_vm_and_native_image(self):
        result = changes.select(['scripts/lib/common.sh'])
        self.assertTrue(result['macos_vm'] and result['image'])

    def test_installer_change_reaches_both_linux_architectures_and_wsl(self):
        result = changes.select(['setup/config/docker.env'])
        self.assertTrue(result['setup'] and result['wsl'] and result['backends'])

    def test_dispatcher_change_and_manual_run_select_every_boundary(self):
        self.assertTrue(all(changes.select(['.github/workflows/ci.yml']).values()))
        self.assertTrue(all(changes.select([], full=True).values()))

    def test_homebrew_pin_does_not_install_windows_or_linux(self):
        result = changes.select(['setup/config/homebrew.env'])
        self.assertTrue(result['macos'])
        self.assertFalse(result['windows'] or result['wsl'] or result['backends'] or result['setup'])

    def test_wsl_rootfs_pin_does_not_install_mac_or_linux(self):
        result = changes.select(['setup/config/wsl.json'])
        self.assertTrue(result['windows'] and result['wsl'])
        self.assertFalse(result['macos'] or result['backends'] or result['setup'])
