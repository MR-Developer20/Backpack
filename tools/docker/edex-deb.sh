#!/bin/sh
set -e
cd /work/touchmode/edex
export npm_config_cache=/tmp/npmcache ELECTRON_CACHE=/tmp/ecache ELECTRON_BUILDER_CACHE=/tmp/ebcache
export USE_SYSTEM_FPM=false DEBUG=electron-builder
echo "=== prebuild (rsync+minify+install into prebuild-src)"
rm -rf prebuild-src dist
rsync -a src/ prebuild-src --exclude node_modules
node prebuild-minify.js 2>&1 | tail -n 3
cd prebuild-src && npm install --no-audit --no-fund 2>&1 | tail -n 4 && cd ..
echo "=== electron-builder deb x64"
./node_modules/.bin/electron-builder build -l --x64 2>&1 | tail -n 25
echo "=== dist output:"; ls -la dist/*.deb 2>&1
