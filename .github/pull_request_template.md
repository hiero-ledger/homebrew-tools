## Description

<!-- What does this PR change and why? -->

## Checklist

- [ ] `brew audit --formula Formula/solo.rb` passes locally (no errors)
- [ ] `brew install --build-from-source Formula/solo.rb` succeeds locally
- [ ] `brew test hiero-ledger/tools/solo` passes
- [ ] If bumping version: `.github/scripts/update-solo-formula.sh <version>` was run; pinned formula generated correctly; no stray `SoloAT...` strings appear in message bodies of the versioned file
- [ ] `license "Apache-2.0"`, `bottle :unneeded`, and `version` fields are correct in all modified formulas
