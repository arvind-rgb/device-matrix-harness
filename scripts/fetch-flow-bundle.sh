#!/usr/bin/env bash
# Downloads the flow tarball (zipped maestro YAMLs + subflows + config) and
# extracts it into ./flows/ in the workspace. Flow YAMLs are NOT committed to
# this repo; they arrive at runtime via the signed URL.
set -euo pipefail

URL="${1:?usage: fetch-flow-bundle.sh <signed_url>}"

curl --fail-with-body --location --silent --show-error \
  --output flows.tar.gz \
  "$URL"

mkdir -p flows
tar -xzf flows.tar.gz -C flows --strip-components=0
echo "fetch-flow-bundle: extracted $(find flows -name '*.yaml' | wc -l) YAMLs"
