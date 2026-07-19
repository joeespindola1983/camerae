# Figma to SwiftUI contract

`camerae.tokens.json` is the versioned handoff contract between the Camerae Figma library and the iOS app.

Sync flow:

1. Read the variables from the Figma Foundations page.
2. Update `camerae.tokens.json` with the changed values.
3. Regenerate `CameraeTokens.generated.swift` and the named color sets in `Assets.xcassets`.
4. Review the diff and run the Camerae build/tests before merging.

Rules:

- Figma custom/brand variables become named iOS assets or generated constants.
- iOS semantic values stay native (`Color.primary`, `Color.secondary`, system backgrounds).
- Screens consume semantic tokens and `CameraeWorkflowTheme`, never raw RGB values.
- Figma device chrome and status bars are reference-only and are not implemented as app UI.
- Outfit and DM Mono typography values are recorded in the manifest, but must only be activated after their licensed font files are bundled in the app.

The Figma file key and Foundations node are stored in the manifest metadata so a future CI exporter can refresh the same source deterministically.
