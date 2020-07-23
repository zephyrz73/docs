#!/bin/bash

# To be perfectly honest, I'm not yet sure why we have to do this, but we do. It's only required
# for Pulumify builds, so it must have something to do with the way we're executing the
# PULUMIFY BUILD command.
# rm -rf node_modules
# yarn cache clean
yarn install

./scripts/build-site.sh preview
