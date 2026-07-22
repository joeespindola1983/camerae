#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/release-gate.sh check [--plan]
  scripts/release-gate.sh firebase --publish [--plan]
  scripts/release-gate.sh appstore --publish [--plan]

Modes:
  check       Run every local release validation without publishing.
  firebase    Validate from qa, then publish to Firebase App Distribution.
  appstore    Validate from release/*, then upload to App Store Connect.

Options:
  --publish   Required explicit authorization for an external upload.
  --plan      Print the enforced stages without running them.
  -h, --help  Show this help.

Local configuration may be stored in ios/Config/Release.local.env.
The file is ignored by Git and must never be committed.
USAGE
}

MODE="${1:-}"
if [[ -z "$MODE" || "$MODE" == "-h" || "$MODE" == "--help" ]]; then
  usage
  [[ -n "$MODE" ]] && exit 0
  exit 2
fi
shift

PUBLISH=0
PLAN_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --publish) PUBLISH=1 ;;
    --plan) PLAN_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

case "$MODE" in
  check) ;;
  firebase|appstore)
    if [[ "$PUBLISH" -ne 1 ]]; then
      echo "$MODE requires --publish; validation alone uses the check mode." >&2
      exit 2
    fi
    ;;
  *) echo "Unknown mode: $MODE" >&2; usage >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$IOS_DIR/.." && pwd)"
LOCAL_ENV="$IOS_DIR/Config/Release.local.env"
TEST_DESTINATION="${TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=latest}"

print_plan() {
  echo "mode: $MODE"
  echo "publish: $([[ "$PUBLISH" -eq 1 ]] && echo yes || echo no)"
  case "$MODE" in
    check)
      echo "required branch: any synchronized release branch"
      echo "destination: none"
      ;;
    firebase)
      echo "required branch: qa"
      echo "destination: Firebase App Distribution"
      ;;
    appstore)
      echo "required branch: release/*"
      echo "destination: App Store Connect"
      ;;
  esac
  echo "git: clean, synchronized commit"
  echo "signing: existing identity and provisioning profile only"
  echo "tests: localization, architecture, Swift, Camerae Processing, Camerae Vision"
  echo "visual evidence: six locales on iPhone and iPad, archived under docs/ui-evidence"
  echo "OpenCV XCFramework: pinned 4.13.0, device and simulator slices"
  echo "build: unsigned device build before signed archive"
}

if [[ "$PLAN_ONLY" -eq 1 ]]; then
  print_plan
  exit 0
fi

if [[ -f "$LOCAL_ENV" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$LOCAL_ENV"
  set +a
fi

fail() {
  echo "Release gate blocked: $*" >&2
  exit 1
}

step() {
  echo
  echo "==> $*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command '$1'"
}

[[ "$(uname -s)" == "Darwin" ]] || fail "iOS releases must run on macOS"
for command in git rg pod xcodebuild cmake ctest security python3; do
  require_command "$command"
done

cd "$ROOT_DIR"

step "Validate Git state"
branch="$(git branch --show-current)"
[[ -n "$branch" ]] || fail "detached HEAD is not a release source"
if ! git diff --quiet || ! git diff --cached --quiet; then
  fail "tracked files have uncommitted changes"
fi
if [[ -n "$(git status --porcelain --untracked-files=all -- ios)" ]]; then
  fail "the ios tree contains untracked files"
fi

case "$MODE" in
  firebase) [[ "$branch" == "qa" ]] || fail "Firebase publication requires branch qa, found $branch" ;;
  appstore) [[ "$branch" == release/* ]] || fail "App Store publication requires release/*, found $branch" ;;
esac

upstream="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" || fail "branch $branch has no upstream"
read -r ahead behind < <(git rev-list --left-right --count HEAD..."$upstream")
[[ "$ahead" == "0" && "$behind" == "0" ]] || fail "$branch is not synchronized with $upstream (ahead $ahead, behind $behind)"

version="$(awk -F '"' '/MARKETING_VERSION:/ { print $2; exit }' "$IOS_DIR/project.yml")"
build="$(awk -F '"' '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "$IOS_DIR/project.yml")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid MARKETING_VERSION in project.yml"
[[ "$build" =~ ^[0-9]+$ ]] || fail "invalid CURRENT_PROJECT_VERSION in project.yml"
if [[ "$MODE" == "appstore" && "$branch" != "release/v$version" ]]; then
  fail "branch $branch does not match MARKETING_VERSION $version"
fi
echo "Source: $branch @ $(git rev-parse --short HEAD), Camerae $version ($build)"

step "Validate local signing"
identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if [[ "$MODE" == "appstore" ]]; then
  [[ "$identities" == *"Apple Distribution"* ]] || fail "no valid Apple Distribution identity exists in the local keychain"
elif [[ "$MODE" == "firebase" ]]; then
  if [[ "$identities" != *"Apple Development"* && "$identities" != *"Apple Distribution"* ]]; then
    fail "no valid Apple signing identity exists in the local keychain"
  fi
fi

step "Install locked CocoaPods dependencies"
(cd "$IOS_DIR" && pod install --deployment)

step "Verify pinned OpenCV XCFramework"
(cd "$IOS_DIR" && ./scripts/verify-opencv-xcframework.sh)

step "Check architecture boundaries"
(cd "$IOS_DIR" && ./scripts/check-architecture.sh)

step "Validate localization catalogs"
(cd "$IOS_DIR" && ./scripts/tests/localization-tests.sh)

step "Run Swift component and integration tests"
(cd "$IOS_DIR" && xcodebuild \
  -workspace Camerae.xcworkspace \
  -scheme Camerae \
  -destination "$TEST_DESTINATION" \
  -derivedDataPath "$ROOT_DIR/.build/release-gate-tests" \
  CODE_SIGNING_ALLOWED=NO \
  test)

step "Generate simulator UI evidence"
(cd "$IOS_DIR" && ./scripts/generate-ui-evidence.sh --device iphone --destination "$TEST_DESTINATION" --all-locales --archive-tracked)
(cd "$IOS_DIR" && ./scripts/generate-ui-evidence.sh --device ipad --all-locales --archive-tracked)

step "Run C++ Camerae Processing and Camerae Vision tests"
cmake -S "$ROOT_DIR/processing" -B "$ROOT_DIR/.build/release-gate-processing" -DBUILD_TESTING=ON
cmake --build "$ROOT_DIR/.build/release-gate-processing" --parallel 2
ctest --test-dir "$ROOT_DIR/.build/release-gate-processing" --output-on-failure

step "Build the generic iOS device target without signing"
(cd "$IOS_DIR" && xcodebuild \
  -workspace Camerae.xcworkspace \
  -scheme Camerae \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$ROOT_DIR/.build/release-gate-device" \
  CODE_SIGNING_ALLOWED=NO \
  build)

if [[ "$MODE" == "check" ]]; then
  echo
  echo "Release gate passed for Camerae $version ($build); nothing was published."
  exit 0
fi

step "Publish Camerae $version ($build)"
export ALLOW_PROVISIONING_UPDATES=0
case "$MODE" in
  firebase) (cd "$IOS_DIR" && ./scripts/distribute-firebase.sh) ;;
  appstore) (cd "$IOS_DIR" && ./scripts/upload-appstore.sh) ;;
esac

echo
echo "Release gate and $MODE publication completed successfully."
