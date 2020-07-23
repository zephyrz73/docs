#!/bin/bash

which node
node -v

which yarn
yarn -v

pwd

yarn cache clean
rm -rf node_modules
yarn install

./scripts/build-site.sh preview
