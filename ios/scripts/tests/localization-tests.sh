#!/usr/bin/env bash
set -euo pipefail

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export IOS_DIR

python3 - <<'PY'
import json
import os
from pathlib import Path

ios = Path(os.environ["IOS_DIR"])
locales = ["pt-BR", "es", "en", "fr", "de", "ru"]

def load(name):
    path = ios / "Camerae" / f"{name}.xcstrings"
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)

def validate_catalog(name, required_keys=()):
    catalog = load(name)
    assert catalog["sourceLanguage"] == "pt-BR", f"{name} source language must be pt-BR"
    strings = catalog["strings"]
    for key in required_keys:
        assert key in strings, f"{name} is missing required key {key}"
    for key, entry in strings.items():
        translations = entry.get("localizations", {})
        for locale in locales:
            unit = translations.get(locale, {}).get("stringUnit", {})
            assert unit.get("state") == "translated", f"{name}:{key} is not translated for {locale}"
            assert unit.get("value", "").strip(), f"{name}:{key} is empty for {locale}"

validate_catalog("Localizable", [
    "home.module.repeatable",
    "home.module.astro",
    "home.module.edit",
    "workflow.tab.configure",
    "workflow.tab.captures",
    "workflow.mode.video",
    "workflow.mode.timelapse",
    "workflow.mode.automatic",
    "workflow.mode.manual",
    "workflow.section.capture",
    "workflow.section.session",
    "workflow.section.adjustments",
    "workflow.section.astro_capture",
    "workflow.section.video",
    "workflow.section.camera",
    "workflow.section.planning",
    "workflow.reference.take_photo",
    "workflow.reference.import",
    "workflow.action.open_camera",
    "workflow.camera.unavailable.title",
    "workflow.camera.status.unavailable",
    "workflow.summary.frames",
    "workflow.planning.capacity",
    "workflow.video.resolution",
    "workflow.video.quality",
])
validate_catalog("InfoPlist", [
    "NSCameraUsageDescription",
    "NSLocationWhenInUseUsageDescription",
    "NSLocationTemporaryUsageDescriptionDictionary.RepeatableAlignment",
])

project = (ios / "project.yml").read_text(encoding="utf-8")
assert "developmentLanguage: pt-BR" in project, "project.yml must use pt-BR as development language"
PY

if rg -n 'Locale\(identifier: "pt_BR"\)' "$IOS_DIR/Camerae" --glob '*.swift'; then
  echo "User-facing formatting must use Locale.current instead of a fixed pt_BR locale" >&2
  exit 1
fi

echo "Localization contract tests passed"
