#!/usr/bin/env bash
# Renders every input in tests/render/inputs/ through the ManagedResource produced
# by the backendtlspolicy-cnp golden compile (instance "test-gateway-default-enabled",
# source namespace "shared-source") and writes the output over the committed
# expected files. Drift is checked with `git diff --exit-code tests/render/expected/`
# — same golden-file model as `make golden-diff`, no hand-rolled assertions.
#
# Run `bash tests/render/run.sh && git diff --exit-code tests/render/expected/`
# locally, or `make test-espejote`. Regenerate the expected files after an
# intentional template change with `make gen-espejote`, then review and commit
# the diff.
#
# NOTE: this renders the *compiled* ManagedResource, so it also guards against
# parameter-substitution regressions (target namespace, gateway label, MR name)
# in component/backendtlspolicy-cnp.jsonnet, not just the template logic.
#
# CAVEAT (offline pre-filtering): espejote does NOT re-apply the context
# labelSelector/namespace offline, so every CNP placed in a scenario's
# ciliumnetworkpolicies context array already carries the label
#   espejote.io/managed-resource: backendtlspolicy-cnp
# and namespace test-gateway-default-enabled, exactly as the cluster would deliver.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTANCE="backendtlspolicy-cnp"
GATEWAY="test-gateway-default-enabled"
MANIFEST="$ROOT/compiled/$INSTANCE/$INSTANCE/$INSTANCE/$GATEWAY/$GATEWAY/ManagedResource-backendtlspolicy-cnp.yaml"
INPUTS="$ROOT/tests/render/inputs"
EXPECTED="$ROOT/tests/render/expected"

if ! command -v espejote >/dev/null 2>&1; then
  echo "espejote not found on PATH — install it from https://github.com/vshn/espejote releases (not vendored in this repo)" >&2
  exit 77
fi

if [ ! -f "$MANIFEST" ]; then
  make -C "$ROOT" golden-diff -e instance="$INSTANCE" >/dev/null
fi
if [ ! -f "$MANIFEST" ]; then
  echo "FAIL: compiled ManagedResource not found at $MANIFEST" >&2
  exit 1
fi

mkdir -p "$EXPECTED"
for input in "$INPUTS"/*.yaml; do
  name="$(basename "$input" .yaml)"
  espejote render "$MANIFEST" --input "$input" >"$EXPECTED/$name.rendered.yaml"
done
echo "rendered $(ls -1 "$INPUTS"/*.yaml | wc -l) scenarios into $EXPECTED"
