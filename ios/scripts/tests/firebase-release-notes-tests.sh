#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/../validate-firebase-release-notes.sh"

expect_failure() {
  local expected="$1"
  shift

  set +e
  local output
  output="$("$VALIDATOR" "$@" 2>&1)"
  local status=$?
  set -e

  if [[ $status -eq 0 ]]; then
    echo "Expected release-note validation to fail" >&2
    exit 1
  fi
  if [[ "$output" != *"$expected"* ]]; then
    echo "Expected output to contain: $expected" >&2
    echo "$output" >&2
    exit 1
  fi
}

expect_success() {
  "$VALIDATOR" "$@" >/dev/null
}

temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

valid_notes_file="$temporary_dir/release-notes.txt"
empty_notes_file="$temporary_dir/empty-release-notes.txt"
printf 'Camerae QA release with Astro Photo and offline sky identification.\n' > "$valid_notes_file"
printf ' \n\t\n' > "$empty_notes_file"

expect_failure "Release notes are required" --text "" --file ""
expect_failure "Release notes cannot contain only whitespace" --text $' \n\t' --file ""
expect_failure "Release notes file does not exist" --text "" --file "$temporary_dir/missing.txt"
expect_failure "Release notes file cannot be empty" --text "" --file "$empty_notes_file"
expect_failure "Choose either release notes text or a release notes file" \
  --text "Detailed notes" \
  --file "$valid_notes_file"

expect_success --text "Detailed Astro Photo QA notes" --file ""
expect_success --text "" --file "$valid_notes_file"

echo "Firebase release notes contract tests passed"
