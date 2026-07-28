#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/ios-build.yml"
PR_TEMPLATE="$ROOT_DIR/.github/pull_request_template.md"
FEATURE_TEMPLATE="$ROOT_DIR/.github/ISSUE_TEMPLATE/feature.yml"
AGENT_RULES="$ROOT_DIR/AGENTS.md"
GITFLOW="$ROOT_DIR/docs/GITFLOW.md"
OPENCV_VERIFIER="$ROOT_DIR/ios/scripts/verify-opencv-xcframework.sh"

fail() {
  echo "PR workflow contract failed: $*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing ${1#"$ROOT_DIR/"}"
}

require_text() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  grep -Eq -- "$pattern" "$file" || fail "$message"
}

require_file "$WORKFLOW"
require_file "$PR_TEMPLATE"
require_file "$FEATURE_TEMPLATE"
require_file "$AGENT_RULES"
require_file "$GITFLOW"
require_file "$OPENCV_VERIFIER"

require_text "$WORKFLOW" '^  pull_request:$' "iOS Build must run for pull requests"
require_text "$WORKFLOW" '^      - develop$' "iOS Build must validate PRs targeting develop"
require_text "$WORKFLOW" "release/\\*\\*" "iOS Build must validate stabilization PRs"
require_text "$WORKFLOW" '^  workflow_dispatch:$' "manual iOS Build diagnostics must remain available"
require_text "$WORKFLOW" '^permissions:$' "workflow permissions must be explicit"
require_text "$WORKFLOW" '^  contents: read$' "iOS Build must use read-only repository access"
require_text "$WORKFLOW" '^concurrency:$' "iOS Build must cancel obsolete PR runs"
require_text "$WORKFLOW" "pull_request\\.draft == false" "full CI must wait until a draft PR is ready"
require_text "$WORKFLOW" 'pr-workflow-tests\.sh' "CI must validate the PR workflow contract"
require_text "$WORKFLOW" '-testLanguage pt-BR' "Swift tests must use the expected PT-BR language"
require_text "$WORKFLOW" '-testRegion BR' "Swift tests must use the expected Brazilian region"

require_text "$PR_TEMPLATE" '^## O que muda$' "PR template must summarize the change"
require_text "$PR_TEMPLATE" '^## Por que entra nesta versão$' "PR template must justify release selection"
require_text "$PR_TEMPLATE" '^## Como validar$' "PR template must describe validation"
require_text "$PR_TEMPLATE" 'CHANGELOG\.md' "PR template must check changelog coverage"
require_text "$PR_TEMPLATE" 'Draft' "PR template must explain draft selection"

require_text "$FEATURE_TEMPLATE" '^name: Funcionalidade ou melhoria$' "feature form must be discoverable"
require_text "$FEATURE_TEMPLATE" 'id: tipo' "feature form must classify work"
require_text "$FEATURE_TEMPLATE" 'id: problema' "feature form must capture the problem"
require_text "$FEATURE_TEMPLATE" 'id: resultado' "feature form must capture the desired result"
require_text "$FEATURE_TEMPLATE" 'id: versao' "feature form must capture release intent"

require_text "$AGENT_RULES" 'Every product or process change uses a short-lived branch and a pull request into `develop`' \
  "repository rules must require PRs into develop"
require_text "$AGENT_RULES" 'Do not commit product or process changes directly to `develop`' \
  "repository rules must prohibit direct development commits"

require_text "$GITFLOW" 'Draft PR' "GitFlow must document draft PRs"
require_text "$GITFLOW" 'Decision queue' "GitFlow must explain how work is selected"
require_text "$GITFLOW" 'target `develop`' "GitFlow must identify the normal PR base"
require_text "$GITFLOW" 'target the active `release/' "GitFlow must route stabilization fixes correctly"

if grep -Eq '(^|[[:space:]])rg([[:space:]]|$)' "$OPENCV_VERIFIER"; then
  fail "OpenCV verification must not depend on ripgrep on GitHub macOS runners"
fi
require_text "$OPENCV_VERIFIER" 'grep -Eq' "OpenCV verification must use a runner-portable matcher"

echo "PR workflow contract passed"
