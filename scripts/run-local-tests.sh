#!/bin/bash
# Run the entry module's local (host) hypium unit tests and FAIL on any
# assertion failure.
#
# Why this exists: `hvigorw ... test` executes the assertions but reports
# BUILD SUCCESSFUL even when an `expect().assertX()` fails — the failure only
# appears as an `ERROR: Error in <case>, ...` / `AssertException` line in the
# log, not in the exit code. Relying on BUILD SUCCESSFUL alone lets a broken
# test pass silently. This wrapper greps the output for those failure lines and
# exits non-zero if any are present, giving a trustworthy pass/fail signal.
set -u

# Defaults are the macOS install. On Windows (git-bash) DevEco lives elsewhere,
# hvigorw is a .js that needs an explicit node, and hvigor shells out to `java`
# for PackageHap — which is only on PATH if we put the bundled JBR there.
DEVECO_WIN="${DEVECO_WIN:-/d/Works/DevEco Studio}"
if [ -z "${DEVECO_SDK_HOME:-}" ] && [ -d "$DEVECO_WIN/sdk" ]; then
  # hvigor rejects a POSIX path here, so hand it the Windows spelling.
  export DEVECO_SDK_HOME="$(cd "$DEVECO_WIN/sdk" && pwd -W | sed 's|/|\\|g')"
  export DEVECO_NODE_HOME="${DEVECO_NODE_HOME:-$DEVECO_WIN/tools/node}"
  export PATH="$DEVECO_WIN/jbr/bin:$PATH"
  HVIGOR_JS="$DEVECO_WIN/tools/hvigor/bin/hvigorw.js"
fi

export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
export DEVECO_NODE_HOME="${DEVECO_NODE_HOME:-/Applications/DevEco-Studio.app/Contents/tools/node}"
HVIGORW="${HVIGORW:-/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# i18n gate first: it is a static check that runs in a second, so a broken
# resource reference should not wait behind a two-minute test build.
NODE_BIN="${DEVECO_NODE_HOME}/bin/node"
[ -x "$NODE_BIN" ] || NODE_BIN="${DEVECO_NODE_HOME}/node"
[ -x "$NODE_BIN" ] || NODE_BIN="node"
if ! "$NODE_BIN" scripts/i18n-check.mjs; then
  echo ""
  echo "LOCAL TESTS: FAIL (i18n check — see above)"
  exit 1
fi
echo ""

if [ -n "${HVIGOR_JS:-}" ] && [ ! -x "$HVIGORW" ]; then
  OUT="$("$NODE_BIN" "$HVIGOR_JS" --mode module -p module=entry@default -p isLocalTest=true test 2>&1)"
else
  OUT="$("$HVIGORW" --mode module -p module=entry@default -p isLocalTest=true test 2>&1)"
fi
echo "$OUT"

echo "$OUT" | grep -qiE "BUILD SUCCESSFUL" || {
  echo ""
  echo "LOCAL TESTS: FAIL (build did not succeed)"
  exit 1
}

FAILS="$(echo "$OUT" | grep -icE "ERROR: Error in|AssertException")"
if [ "$FAILS" -ne 0 ]; then
  echo ""
  echo "LOCAL TESTS: FAIL ($FAILS assertion-failure line(s) — see 'ERROR: Error in ...' above)"
  exit 1
fi

echo ""
echo "LOCAL TESTS: PASS (build succeeded, 0 assertion failures)"
