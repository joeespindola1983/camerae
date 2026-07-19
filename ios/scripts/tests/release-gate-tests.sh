#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/release-gate.sh"
IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT_DIR="$(cd "$IOS_DIR/.." && pwd)"

expect_contains() {
  local output="$1"
  local expected="$2"
  if [[ "$output" != *"$expected"* ]]; then
    echo "Expected output to contain: $expected" >&2
    echo "$output" >&2
    exit 1
  fi
}

check_plan="$($SCRIPT check --plan)"
expect_contains "$check_plan" "mode: check"
expect_contains "$check_plan" "publish: no"
expect_contains "$check_plan" "git: clean, synchronized commit"
expect_contains "$check_plan" "tests: architecture, Swift, Camerae Processing, Camerae Vision"

firebase_plan="$($SCRIPT firebase --plan --publish)"
expect_contains "$firebase_plan" "mode: firebase"
expect_contains "$firebase_plan" "required branch: qa"
expect_contains "$firebase_plan" "publish: yes"
expect_contains "$firebase_plan" "destination: Firebase App Distribution"

appstore_plan="$($SCRIPT appstore --plan --publish)"
expect_contains "$appstore_plan" "mode: appstore"
expect_contains "$appstore_plan" "required branch: release/*"
expect_contains "$appstore_plan" "publish: yes"
expect_contains "$appstore_plan" "destination: App Store Connect"

set +e
missing_publish_output="$($SCRIPT firebase --plan 2>&1)"
missing_publish_status=$?
set -e
if [[ $missing_publish_status -eq 0 ]]; then
  echo "Firebase publication must require --publish" >&2
  exit 1
fi
expect_contains "$missing_publish_output" "requires --publish"

if ! rg -q 'ALLOW_PROVISIONING_UPDATES="\$\{ALLOW_PROVISIONING_UPDATES:-0\}"' "$IOS_DIR/scripts/distribute-firebase.sh"; then
  echo "Firebase distribution must disable provisioning updates by default" >&2
  exit 1
fi
if ! rg -q 'ALLOW_PROVISIONING_UPDATES="\$\{ALLOW_PROVISIONING_UPDATES:-0\}"' "$IOS_DIR/scripts/upload-appstore.sh"; then
  echo "App Store upload must disable provisioning updates by default" >&2
  exit 1
fi
if rg -n '^ +"\$\{(provisioning_args|build_settings)\[@\]\}" \\$' "$IOS_DIR/scripts/distribute-firebase.sh"; then
  echo "Firebase distribution must not expand optional empty arrays under set -u" >&2
  exit 1
fi
if rg -n '^  (push|pull_request):' "$ROOT_DIR/.github/workflows"/*.yml; then
  echo "Release workflows must not run automatically" >&2
  exit 1
fi

echo "Release gate contract tests passed"
