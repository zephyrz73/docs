#!/bin/bash

which node
node -v

which yarn
yarn -v

pwd

yarn install
yarn add --force node-sass

./scripts/build-site.sh preview
