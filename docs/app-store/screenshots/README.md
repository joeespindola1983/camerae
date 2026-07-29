# App Store screenshots

This directory contains versioned product-page screenshot candidates, organized
by App Store localization and device family.

## Structure

```text
<locale>/
  iphone/
  ipad/
```

Only publication candidates belong here. Generated drafts, intermediate crops,
and local exports remain outside the repository.

Before upload:

1. compare every represented control and populated state with the shipping build;
2. replace concept-only UI with fresh device-captured UI when exact fidelity is
   required;
3. verify dimensions, alpha transparency, copy, localization, and screenshot
   order;
4. run the release gate for the target release branch.

The Repeatable marketing compositions can be reproduced with
`scripts/generate-repeatable-app-store-screenshots.mjs`. The script expects six
pre-extracted, native-resolution PNG frames and produces the official iPhone
6.9-inch and iPad 13-inch sizes without generative image editing.
