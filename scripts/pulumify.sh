#!/bin/bash

# To be perfectly honest, I'm not yet sure why we have to do this, but we do. It's only
# required for Pulumify builds, so it must have something to do with how we're executing
# the PULUMIFY BUILD command, how Make targets are executed, and how the environment in
# the Docker container is constructed.
yarn cache clean
rm -rf node_modules
yarn config set unsafe-perm true
yarn install

./scripts/build-site.sh preview
