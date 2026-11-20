#!/usr/bin/env bash
# Builds dist/packRat-<version>.zip for a manual CurseForge upload: one packRat/
# folder with the .toc (version filled in), the Lua files, Bindings.xml,
# embeds.xml, Media, the embedded Libs and the license. Runs the tests first.
#   tools/package.sh [version]     (default: the version in CHANGELOG.md)
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"

version="${1:-$(grep -m1 -oE '^## [0-9]+\.[0-9]+\.[0-9]+' CHANGELOG.md | cut -c4-)}"
[[ -n "$version" ]] || { echo "No version given and none found in CHANGELOG.md" >&2; exit 1; }

for lib in LibStub CallbackHandler-1.0 LibDataBroker-1.1 LibDBIcon-1.0; do
    [[ -d "Libs/$lib" ]] || { echo "Libs/$lib is missing (the minimap button needs it)" >&2; exit 1; }
done

lua5.1 tests/run.lua
lua5.1 tests/smoke.lua > /dev/null && echo "smoke OK"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
dest="$stage/packRat"
mkdir -p "$dest"

sed "s/@project-version@/$version/" packRat.toc > "$dest/packRat.toc"
# Every file the .toc loads, plus what the client reads on its own.
grep -E '\.(lua|xml)$' packRat.toc | while read -r file; do cp "$file" "$dest/"; done
cp Bindings.xml LICENSE "$dest/"
cp -r Media Libs "$dest/"

mkdir -p dist
zip_path="dist/packRat-$version.zip"
rm -f "$zip_path"
# Python's zipfile instead of zip(1), which isn't installed everywhere.
python3 - "$stage" "$repo/$zip_path" <<'PY'
import os, sys, zipfile
stage, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(os.path.join(stage, "packRat")):
        dirs.sort()
        rel = os.path.relpath(root, stage)
        z.write(root, rel + "/")
        for name in sorted(files):
            z.write(os.path.join(root, name), os.path.join(rel, name))
PY
echo "Built $zip_path"
python3 -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); print(len(z.namelist()), 'entries')" "$zip_path"
