#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/validate-firebase-release-notes.sh --text TEXT --file FILE

Exactly one non-empty release-note source is required. Pass an empty value for
the unused source.
USAGE
}

release_notes=""
release_notes_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --text)
      release_notes="${2-}"
      shift 2
      ;;
    --file)
      release_notes_file="${2-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -n "$release_notes" && -n "$release_notes_file" ]]; then
  echo "Choose either release notes text or a release notes file, not both." >&2
  exit 1
fi

if [[ -z "$release_notes" && -z "$release_notes_file" ]]; then
  echo "Release notes are required for every Firebase distribution." >&2
  exit 1
fi

if [[ -n "$release_notes" ]]; then
  if [[ ! "$release_notes" =~ [^[:space:]] ]]; then
    echo "Release notes cannot contain only whitespace." >&2
    exit 1
  fi
  exit 0
fi

if [[ ! -f "$release_notes_file" ]]; then
  echo "Release notes file does not exist: $release_notes_file" >&2
  exit 1
fi

file_contents="$(<"$release_notes_file")"
if [[ ! "$file_contents" =~ [^[:space:]] ]]; then
  echo "Release notes file cannot be empty or contain only whitespace." >&2
  exit 1
fi
