#!/bin/bash

set -euxo pipefail

which node
node -v

which yarn
yarn -v

yarn add --force node-sass

./scripts/build-site.sh preview
