#!/usr/bin/env bash
# Downloads an artifact from a signed URL. URL is passed as $1 and may contain
# query parameters; quoting + curl --fail-with-body ensure a non-zero exit on
# any 4xx/5xx response so the job fails fast instead of silently producing
# an empty file.
set -euo pipefail

URL="${1:?usage: fetch-build.sh <signed_url> <out_path>}"
OUT="${2:?usage: fetch-build.sh <signed_url> <out_path>}"

curl --fail-with-body --location --silent --show-error \
  --output "$OUT" \
  "$URL"

if [[ ! -s "$OUT" ]]; then
  echo "fetch-build: downloaded file is empty" >&2
  exit 1
fi

echo "fetch-build: $(stat -c%s "$OUT" 2>/dev/null || stat -f%z "$OUT") bytes → $OUT"
