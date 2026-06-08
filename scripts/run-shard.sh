#!/usr/bin/env bash
# Runs one shard's slice of a Maestro suite. Bundle-agnostic + brand-free:
# all app/test identifiers come from the bundle's config.yaml at runtime, never
# hardcoded here.
#
# Usage:  run-shard.sh <platform> <shard_index> <shard_total> [apk_path]
#   platform    : android | ios
#   apk_path    : optional; Android install (iOS uses the booted simulator)
#
# config.yaml keys consumed:
#   APP_ID_ANDROID / APP_ID_IOS  -> resolved to APP_ID for the platform
#   any other KEY: "value" lines  -> exported + passed to maestro via -e
#
# Output: ./shard-output/results.junit.xml  +  ./shard-output/screenshots/
set -uo pipefail

# Ensure the Maestro CLI is on PATH even when this script runs inside the
# android-emulator-runner action's shell (which doesn't always inherit the
# $GITHUB_PATH additions from the install step).
export PATH="$HOME/.maestro/bin:$PATH"

PLATFORM="${1:?platform}"
SHARD_INDEX="${2:?shard_index}"
SHARD_TOTAL="${3:?shard_total}"
BUILD_PATH="${4:-}"

OUT="$PWD/shard-output"
mkdir -p "$OUT/screenshots"

if [ "$PLATFORM" = "android" ] && [ -n "$BUILD_PATH" ]; then
  adb install -r "$BUILD_PATH" || true
fi

cd flows

# ── Load config.yaml (KEY: "value" lines) into the environment + collect the
#    list of keys so we can forward them all to Maestro generically. ──────────
ENV_ARGS=()
APP_ID=""
if [ -f config.yaml ]; then
  while IFS= read -r line; do
    case "$line" in \#*|"") continue ;; esac
    printf '%s' "$line" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:' || continue
    k=$(printf '%s' "$line" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:.*/\1/')
    v=$(printf '%s' "$line" | sed -E 's/^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*//; s/[[:space:]]*#.*$//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')
    export "$k=$v"
    ENV_ARGS+=( -e "$k=$v" )
  done < config.yaml
fi

# Resolve the per-platform app id into a single APP_ID var that flows reference.
if [ "$PLATFORM" = "android" ]; then
  APP_ID="${APP_ID_ANDROID:-}"
else
  APP_ID="${APP_ID_IOS:-}"
fi
[ -n "$APP_ID" ] && ENV_ARGS+=( -e "APP_ID=$APP_ID" )
echo "platform=$PLATFORM app_id=${APP_ID:-<none>}"

# ── Slice the TC list for this shard (portable; no mapfile) ─────────────────
TMP_LIST=$(ls TC-*.yaml 2>/dev/null | sort)
TOTAL=$(printf '%s\n' "$TMP_LIST" | grep -c . || true)
if [ "${TOTAL:-0}" -eq 0 ]; then
  printf '<?xml version="1.0" encoding="UTF-8"?><testsuites><testsuite name="empty" tests="0"/></testsuites>\n' > "$OUT/results.junit.xml"
  exit 0
fi
START=$(( SHARD_INDEX * TOTAL / SHARD_TOTAL ))
END=$(( (SHARD_INDEX + 1) * TOTAL / SHARD_TOTAL ))
COUNT=$(( END - START ))
echo "shard $SHARD_INDEX/$SHARD_TOTAL -> $COUNT of $TOTAL"

RUNDIR="$PWD/../shard-run"
rm -rf "$RUNDIR"; mkdir -p "$RUNDIR"
[ -d subflows ] && cp -R subflows "$RUNDIR/subflows"
[ -f config.yaml ] && cp config.yaml "$RUNDIR/config.yaml"
i=0
printf '%s\n' "$TMP_LIST" | while IFS= read -r f; do
  [ "$i" -ge "$START" ] && [ "$i" -lt "$END" ] && cp "$f" "$RUNDIR/"
  i=$(( i + 1 ))
done

if [ "$COUNT" -eq 0 ]; then
  printf '<?xml version="1.0" encoding="UTF-8"?><testsuites><testsuite name="empty" tests="0"/></testsuites>\n' > "$OUT/results.junit.xml"
  exit 0
fi

# ── Run Maestro on the slice dir. Non-zero exit is normal when flows fail; we
#    still want the JUnit. ─────────────────────────────────────────────────────
maestro test --format junit --output "$OUT/results.junit.xml" "${ENV_ARGS[@]}" "$RUNDIR"
echo "maestro exit=$?"

[ -d "$HOME/.maestro/tests" ] && find "$HOME/.maestro/tests" -name '*.png' -exec cp {} "$OUT/screenshots/" \; 2>/dev/null || true
[ -f "$OUT/results.junit.xml" ] || printf '<?xml version="1.0" encoding="UTF-8"?><testsuites><testsuite name="no-output" tests="0"/></testsuites>\n' > "$OUT/results.junit.xml"
exit 0
