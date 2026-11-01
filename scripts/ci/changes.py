#!/usr/bin/env python3
"""Select platform boundaries from changed paths; no third-party dependencies."""
import argparse
import os
import subprocess
from pathlib import Path


def select(paths, *, full=False):
    result = dict.fromkeys(('windows', 'backends', 'macos', 'macos_vm', 'wsl', 'image', 'setup'), full)
    for path in paths:
        # Workflow edits must exercise the edited workflow, including the dispatcher.
        common = path in ('.github/workflows/ci.yml', 'scripts/ci/changes.py')
        workflow = lambda name: path == f'.github/workflows/{name}.yml'
        linux = path.startswith(('setup/ubuntu2404/', 'setup/config/'))
        windows = path.startswith(('setup/windows/', 'tests/windows'))
        macos = path.startswith(('setup/macos/', 'tests/test_macos', 'tests/test_homebrew', 'tests/test_commands'))
        shared = path.startswith(('scripts/lib/', 'compose/')) or path == 'versions.env'
        ci_vm = path.startswith('scripts/ci/macos-')
        result['windows'] |= common or windows or linux or workflow('windows')
        result['backends'] |= common or linux or path in ('tests/probe_backends.py', 'tests/test_setup.py') or workflow('backends')
        result['macos'] |= common or macos or linux or shared or path in ('tests/probe_backends.py', 'tests/test_login_browser.py') or workflow('macos')
        result['macos_vm'] |= common or ci_vm or macos or shared or workflow('macos-vm')
        result['wsl'] |= common or windows or linux or workflow('windows-wsl')
        result['image'] |= common or shared or path.startswith(('containers/', 'examples/', 'scripts/')) or workflow('image')
        result['setup'] |= common or linux or workflow('ubuntu-setup')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--base')
    parser.add_argument('--head', default='HEAD')
    parser.add_argument('--full', action='store_true')
    args = parser.parse_args()
    if args.full:
        paths = []
    else:
        if not args.base or set(args.base) == {'0'}:
            parser.error('A valid base commit is required (or use --full).')
        paths = subprocess.check_output(['git', 'diff', '--name-only', '-z', args.base, args.head], text=True).split('\0')
    lines = [f'{key}={str(value).lower()}' for key, value in select(paths, full=args.full).items()]
    print('\n'.join(lines))
    if os.environ.get('GITHUB_OUTPUT'):
        with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
            output.write('\n'.join(lines) + '\n')
