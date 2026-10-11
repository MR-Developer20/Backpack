#!/bin/sh
# Install deps, rebuild node-pty against the bundled Electron, for the vendored eDEX-UI fork.
# Run inside the backpack-edex container (see tools/docker/Dockerfile.edex).
#   docker run --rm -v $PWD:/work -w /work/touchmode/edex backpack-edex sh /work/scripts/build-edex.sh
set -e
cd "$(dirname "$0")/../touchmode/edex"
export npm_config_cache=/tmp/npmcache
npm install --no-audit --no-fund
cd src && npm install --no-audit --no-fund && cd ..
EV=$(python3 -c "import json;print(json.load(open('node_modules/electron/package.json'))['version'])")
echo "rebuilding node-pty against electron $EV"
cd src && ../node_modules/.bin/electron-rebuild -f -w node-pty --version "$EV" && cd ..
echo "eDEX build OK (electron $EV, node-pty rebuilt)"
