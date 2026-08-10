#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROOT_DIR="$(cd "$IOS_DIR/.." && pwd)"

fail() {
  echo "Environment contract failed: $*" >&2
  exit 1
}

assert_file_value() {
  local file="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$file")"
  [[ "$actual" == "$expected" ]] \
    || fail "$file must set $key to $expected, found $actual"
}

QA_BUNDLE_ID="com.espindola.camerae.qa"
PRODUCTION_BUNDLE_ID="com.espindola.camerae"
QA_FIREBASE_APP_ID="1:413701042509:ios:74c9e8eb4ed40d45d20704"
PRODUCTION_FIREBASE_APP_ID="1:413701042509:ios:b08c2a5a1594459dd20704"
QA_FIREBASE_PLIST="$IOS_DIR/Config/Firebase/QA/GoogleService-Info.plist"
PRODUCTION_FIREBASE_PLIST="$IOS_DIR/Config/Firebase/Production/GoogleService-Info.plist"

[[ -f "$QA_FIREBASE_PLIST" ]] || fail "QA Firebase plist is missing"
[[ -f "$PRODUCTION_FIREBASE_PLIST" ]] || fail "production Firebase plist is missing"

assert_file_value "$QA_FIREBASE_PLIST" BUNDLE_ID "$QA_BUNDLE_ID"
assert_file_value "$QA_FIREBASE_PLIST" GOOGLE_APP_ID "$QA_FIREBASE_APP_ID"
assert_file_value "$PRODUCTION_FIREBASE_PLIST" BUNDLE_ID "$PRODUCTION_BUNDLE_ID"
assert_file_value "$PRODUCTION_FIREBASE_PLIST" GOOGLE_APP_ID "$PRODUCTION_FIREBASE_APP_ID"

rg -q "^PRODUCT_BUNDLE_IDENTIFIER = $QA_BUNDLE_ID$" "$IOS_DIR/Config/Debug.xcconfig" \
  || fail "Debug must install the QA app"
rg -q "^PRODUCT_BUNDLE_IDENTIFIER = $QA_BUNDLE_ID$" "$IOS_DIR/Config/QA.xcconfig" \
  || fail "QA archives must use the QA bundle identifier"
rg -q "^PRODUCT_BUNDLE_IDENTIFIER = $QA_BUNDLE_ID$" "$IOS_DIR/Config/QADebug.xcconfig" \
  || fail "QA Debug must install the QA app"
rg -q "^PRODUCT_BUNDLE_IDENTIFIER = $PRODUCTION_BUNDLE_ID$" "$IOS_DIR/Config/Release.xcconfig" \
  || fail "Release archives must use the production bundle identifier"

rg -q '^CAMERAE_DISPLAY_NAME = Camerae QA$' "$IOS_DIR/Config/Debug.xcconfig" \
  || fail "Debug must be visibly identified as Camerae QA"
rg -q '^CAMERAE_DISPLAY_NAME = Camerae QA$' "$IOS_DIR/Config/QA.xcconfig" \
  || fail "QA archives must be visibly identified as Camerae QA"
rg -q '^CAMERAE_DISPLAY_NAME = Camerae$' "$IOS_DIR/Config/Release.xcconfig" \
  || fail "Release must retain the Camerae display name"
rg -q '^ASSETCATALOG_COMPILER_APPICON_NAME = AppIconQA$' "$IOS_DIR/Config/Debug.xcconfig" \
  || fail "Debug must use the QA-badged app icon"
rg -q '^ASSETCATALOG_COMPILER_APPICON_NAME = AppIconQA$' "$IOS_DIR/Config/QA.xcconfig" \
  || fail "QA archives must use the QA-badged app icon"
rg -q '^ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon$' "$IOS_DIR/Config/Release.xcconfig" \
  || fail "Release must retain the production app icon"
rg -q '^DEVELOPMENT_TEAM = V6JPGVRWCS$' "$IOS_DIR/Config/Signing.xcconfig" \
  || fail "all worktrees must inherit the Camerae development team"
rg -q '^CODE_SIGN_STYLE = Automatic$' "$IOS_DIR/Config/Debug.xcconfig" \
  || fail "Debug must use automatic signing in Xcode"
rg -q '^PROVISIONING_PROFILE_SPECIFIER\[sdk=iphoneos\*\] = *$' "$IOS_DIR/Config/Debug.xcconfig" \
  || fail "Debug must let Xcode select its development profile"
rg -q '^CODE_SIGN_STYLE = Automatic$' "$IOS_DIR/Config/QA.xcconfig" \
  || fail "QA must use automatic signing in Xcode"
rg -q '^CODE_SIGN_IDENTITY = Apple Development$' "$IOS_DIR/Config/QA.xcconfig" \
  || fail "QA device builds must use an Apple Development identity"
rg -q '^PROVISIONING_PROFILE_SPECIFIER\[sdk=iphoneos\*\] = *$' "$IOS_DIR/Config/QA.xcconfig" \
  || fail "QA must let Xcode select its development profile"
rg -q '^CAMERAE_CRASHLYTICS_COLLECTION_ENABLED = YES$' "$IOS_DIR/Config/QADebug.xcconfig" \
  || fail "QA Debug must allow consent-controlled Firebase collection"
rg -q '^CODE_SIGN_STYLE = Automatic$' "$IOS_DIR/Config/QADebug.xcconfig" \
  || fail "QA Debug must use automatic signing in Xcode"
rg -q '^PROVISIONING_PROFILE_SPECIFIER\[sdk=iphoneos\*\] = *$' "$IOS_DIR/Config/QADebug.xcconfig" \
  || fail "QA Debug must let Xcode select its development profile"

rg -q '^\s+QA: release$' "$IOS_DIR/project.yml" \
  || fail "XcodeGen must declare QA as a release configuration"
rg -q '^\s+QADebug: debug$' "$IOS_DIR/project.yml" \
  || fail "XcodeGen must declare a runnable QA Debug configuration"
rg -q '^\s+Camerae QA:$' "$IOS_DIR/project.yml" \
  || fail "XcodeGen must declare the Camerae QA scheme"
rg -q '^\s+archive:$' "$IOS_DIR/project.yml" \
  || fail "XcodeGen schemes must declare archive actions"
rg -q '^\s+config: QA$' "$IOS_DIR/project.yml" \
  || fail "Camerae QA must archive with the QA configuration"
rg -q '^\s+config: QADebug$' "$IOS_DIR/project.yml" \
  || fail "Camerae QA must run with the telemetry-enabled QA Debug configuration"
rg -q '"-FIRDebugEnabled": true' "$IOS_DIR/project.yml" \
  || fail "Camerae QA must identify development devices in Firebase DebugView"
rg -q 'CFBundleDisplayName: \$\(CAMERAE_DISPLAY_NAME\)' "$IOS_DIR/project.yml" \
  || fail "the app display name must come from the environment configuration"
rg -q 'copy-firebase-config\.sh' "$IOS_DIR/project.yml" \
  || fail "the build must embed exactly one environment-specific Firebase plist"
rg -q '^        DEVELOPMENT_TEAM: V6JPGVRWCS$' "$IOS_DIR/project.yml" \
  || fail "XcodeGen must preserve the Camerae development team"

rg -q "'QA' => :release" "$IOS_DIR/Podfile" \
  || fail "CocoaPods must map QA to a release configuration"
rg -q "'QADebug' => :debug" "$IOS_DIR/Podfile" \
  || fail "CocoaPods must map QA Debug to a debug configuration"

rg -q 'SCHEME="Camerae QA"' "$IOS_DIR/scripts/distribute-firebase.sh" \
  || fail "Firebase distribution must archive the Camerae QA scheme"
rg -q 'CONFIGURATION="\$\{CONFIGURATION:-QA\}"' "$IOS_DIR/scripts/distribute-firebase.sh" \
  || fail "Firebase distribution must default to the QA configuration"
rg -q "$QA_FIREBASE_APP_ID" "$IOS_DIR/scripts/distribute-firebase.sh" \
  || fail "Firebase distribution must default to the QA Firebase app"
rg -Fq "EXPECTED_BUNDLE_ID=\"\${EXPECTED_BUNDLE_ID:-$QA_BUNDLE_ID}\"" "$IOS_DIR/scripts/distribute-firebase.sh" \
  || fail "Firebase distribution must enforce the QA bundle identifier"
rg -q 'validate-ipa-environment\.sh' "$IOS_DIR/scripts/distribute-firebase.sh" \
  || fail "Firebase distribution must validate the exported IPA"
rg -q '<key>provisioningProfiles</key>' "$IOS_DIR/scripts/distribute-firebase.sh" \
  || fail "Firebase export must map the QA bundle to its Ad Hoc profile"

rg -q 'EXPECTED_BUNDLE_ID="com\.espindola\.camerae"' "$IOS_DIR/scripts/upload-appstore.sh" \
  || fail "App Store upload must enforce the production bundle identifier"
rg -q 'validate-archive-environment\.sh' "$IOS_DIR/scripts/upload-appstore.sh" \
  || fail "App Store upload must validate the archive before export"

if git -C "$ROOT_DIR" ls-files '*.mobileprovision' | rg -q .; then
  fail "provisioning profiles must never be committed"
fi
rg -q '^\*\.mobileprovision$' "$ROOT_DIR/.gitignore" \
  || fail ".gitignore must reject provisioning profiles"

rg -q 'environment-contract-tests\.sh' "$IOS_DIR/scripts/release-gate.sh" \
  || fail "release gate must validate environment separation"
rg -q 'simctl uninstall "\$SIMULATOR_UDID" com\.espindola\.camerae\.qa' "$IOS_DIR/scripts/generate-ui-evidence.sh" \
  || fail "UI evidence must reset the QA bundle before deterministic screenshots"

QA_ICON_DIR="$IOS_DIR/Camerae/Assets.xcassets/AppIconQA.appiconset"
[[ -f "$QA_ICON_DIR/Contents.json" ]] || fail "QA app icon set is missing"
for icon in Icon-20.png Icon-20@2x.png Icon-20@3x.png Icon-29.png Icon-29@2x.png Icon-29@3x.png Icon-40.png Icon-40@2x.png Icon-40@3x.png Icon-60@2x.png Icon-60@3x.png Icon-76.png Icon-76@2x.png Icon-83.5@2x.png Icon-1024.png; do
  [[ -s "$QA_ICON_DIR/$icon" ]] || fail "QA app icon is missing $icon"
done

echo "QA and production environment contract tests passed"
