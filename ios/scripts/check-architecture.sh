#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if rg -n '^import (SwiftUI|UIKit|AVFoundation|ImageIO)$' "$ROOT/CameraeCore"; then
    echo "CameraeCore must remain independent from UI and media frameworks" >&2
    exit 1
fi

if rg -n 'ThumbnailCache' "$ROOT/Camerae"; then
    echo "Legacy ThumbnailCache references are forbidden; use ThumbnailPipeline" >&2
    exit 1
fi

if rg -n 'firstReferenceFrameURL\(\)|latestSessionSummaryWithFrames\(\)' "$ROOT/Camerae/AppRootView.swift"; then
    echo "Project rows must consume persisted summaries instead of scanning sessions" >&2
    exit 1
fi

echo "Architecture checks passed"
