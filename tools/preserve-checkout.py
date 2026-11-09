"""Create and verify local history plus exact tracked-byte recovery, never delete.

All destination directories must be new. Archives exclude ignored dependencies,
credentials and generated caches by using only Git's explicit tracked-file list.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--recovery', type=Path, required=True)
parser.add_argument('--restore', type=Path, required=True)
args = parser.parse_args()
source = args.source.resolve(strict=True)
recovery = args.recovery.resolve()
restore = args.restore.resolve()
assert recovery != source and restore != source and recovery != restore
assert not recovery.exists() and not restore.exists(), 'Use new recovery/restore directories'
assert source not in restore.parents, 'Fresh restore must be separate from source'
recovery.mkdir(parents=True)

def git(*command, cwd=source):
    return subprocess.check_output(['git', '-C', str(cwd), *command], stderr=subprocess.STDOUT)

def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        while chunk := handle.read(1048576):
            digest.update(chunk)
    return digest.hexdigest()

status = git('status', '--porcelain').decode().strip()
assert not status, 'Commit intended source/evidence first; never silently drop working changes'
head = git('rev-parse', 'HEAD').decode().strip()
names = [name.decode('utf-8') for name in git('ls-files', '-z').split(b'\0') if name]
assert names
manifest = {}
for name in names:
    pure = PurePosixPath(name)
    assert not pure.is_absolute() and '..' not in pure.parts
    path = (source / name).resolve(strict=True)
    assert source in path.parents and path.is_file()
    manifest[name] = {'bytes': path.stat().st_size, 'sha256': sha(path)}
bundle = recovery / 'history.bundle'
git('bundle', 'create', str(bundle), '--all')
git('bundle', 'verify', str(bundle))
archive = recovery / 'tracked-exact.zip'
with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as output:
    for name in names:
        output.write(source / name, name)
subprocess.run(['git', 'clone', '--no-hardlinks', str(bundle), str(restore)], check=True, capture_output=True)
assert git('rev-parse', 'HEAD', cwd=restore).decode().strip() == head
with zipfile.ZipFile(archive) as retained:
    assert sorted(retained.namelist()) == sorted(names)
    for name in retained.namelist():
        data = retained.read(name)
        assert len(data) == manifest[name]['bytes']
        assert hashlib.sha256(data).hexdigest() == manifest[name]['sha256']
        target = (restore / name).resolve()
        assert restore in target.parents and '..' not in PurePosixPath(name).parts
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
failures = [name for name, item in manifest.items()
            if sha(restore / name) != item['sha256'] or (restore / name).stat().st_size != item['bytes']]
assert not failures, failures
restored_status = git('status', '--porcelain', cwd=restore).decode().strip()
assert not restored_status, 'Exact tracked overlay must also leave a clean Git restore'
report = {'status': 'PASS', 'kind': 'local full Git history plus exact tracked-byte archive and fresh restore',
          'source': str(source), 'head': head, 'trackedFiles': len(names), 'restore': str(restore),
          'bundleSha256': sha(bundle), 'archiveSha256': sha(archive),
          'restoredGitStatus': restored_status, 'cloneMode': '--no-hardlinks',
          'archiveEntriesReadBack': len(names), 'failures': failures}
(recovery / 'tracked-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
(recovery / 'proof.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
