#!/usr/bin/env bash
# Posts a shard's results to the dashboard callback URL.
#
# Usage:  callback.sh <callback_base> <bearer_token> <run_id> <platform> <shard_index>
#
# callback_base is the workflow's `callback_url` input (passed at dispatch time,
# never hardcoded). We append the run_id + shard tuple:
#   POST $callback_base/$run_id/shard/$platform/$shard_index/result
#
# Body shape:  { "junit_xml": "<...>" }
#
# If shard-output/results.junit.xml doesn't exist (early-step failure), we
# still POST so BugBhook can mark the shard as failed/done with empty results.
set -euo pipefail

CB_BASE="${1:?callback_base}"
TOKEN="${2:?token}"
RUN_ID="${3:?run_id}"
PLATFORM="${4:?platform}"
SHARD_INDEX="${5:?shard_index}"

URL="$CB_BASE/$RUN_ID/shard/$PLATFORM/$SHARD_INDEX/result"

JUNIT_XML=""
if [[ -f shard-output/results.junit.xml ]]; then
  JUNIT_XML=$(cat shard-output/results.junit.xml)
fi

# Build the JSON payload — jq is preinstalled on every GitHub runner.
PAYLOAD=$(jq -n \
  --arg xml "$JUNIT_XML" \
  '{ junit_xml: $xml }')

# --fail-with-body keeps the response body visible AND exits non-zero on HTTP
# >= 400, so the workflow Callback step fails loudly when BugBhook rejects.
HTTP_CODE=$(curl --location --silent --show-error \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  -d "$PAYLOAD" \
  -w "\nHTTP %{http_code}\n" \
  --output - \
  "$URL" | tee /dev/stderr | awk '/^HTTP/ {print $2}')

if [[ -z "$HTTP_CODE" || "$HTTP_CODE" -ge 400 ]]; then
  echo "callback: POST to $URL failed (HTTP $HTTP_CODE)" >&2
  exit 1
fi

echo "callback: posted $PLATFORM shard $SHARD_INDEX (HTTP $HTTP_CODE)"
