# GitHub Copilot Instructions

This repository is a **Homebrew tap** — it contains Ruby formula files, not application code. The conventions here follow the [Homebrew Formula API](https://rubydoc.brew.sh/Formula).

## Repository Structure

- `Formula/solo.rb` — current/latest formula, generated from `solo.template.rb` by the update script; do not hand-edit version or SHA fields
- `Formula/solo.template.rb` — source of truth for formula logic; contains `__SOLO_VERSION__` and `__SOLO_SHA256__` placeholders
- `Formula/solo@<x.y.z>.rb` — frozen versioned snapshots; class is named `SoloAT<version-nodots>`; never hand-edit
- `Formula/hiero-cli.rb` — simpler formula for the Hedera CLI; updated manually
- `.github/scripts/update-solo-formula.sh` — bumps `solo.rb` to a new version and creates the versioned snapshot

## Required Formula Fields

Every formula must have:
```ruby
license "Apache-2.0"
bottle :unneeded  # for npm-based formulas with no compiled artifact
```

Tests must assert output, not just exit code:
```ruby
test do
  assert_match(/something/i, shell_output("#{bin}/binary --help"))
end
```

## Things to Never Do

1. **Never use `Language::Node`** — it was removed from Homebrew in 2023. Use `std_npm_args` for npm installs:
   ```ruby
   system "npm", "install", *std_npm_args
   ```

2. **Never use backticks for subprocesses** — use `Utils.safe_popen_read` or `shell_output`:
   ```ruby
   # Wrong:
   output = `which -a solo`.strip
   # Right:
   output = Utils.safe_popen_read("which", "-a", "solo").strip
   ```

3. **Never call `odie` in `post_install`** — `odie` marks the keg broken. Use `opoo` + `return`:
   ```ruby
   def post_install
     return unless some_problem?
     opoo "Warning message with instructions."
   end
   ```

4. **Never use `s/Solo/SoloAT.../g` in the update script** — it corrupts user-facing strings. Only the class declaration line should change.

5. **Never hand-edit version/sha256 fields in `solo.rb`** — run the update script instead.

## How the Template + Update Script Work

```
solo.template.rb  ──(script copies + substitutes)──►  solo.rb (new version)
solo.rb (old)     ──(script copies + renames class)──► solo@<old-version>.rb
```

The script (`update-solo-formula.sh`) does everything; the workflow (`update-solo-formula.yml`) calls it with the target version.

## Local Validation

```bash
brew audit --formula Formula/solo.rb
HOMEBREW_NO_SOLO_CACHE=1 brew install --build-from-source Formula/solo.rb
brew test hiero-ledger/tools/solo
shellcheck .github/scripts/update-solo-formula.sh
rubocop --config .rubocop.yml Formula/solo.rb Formula/hiero-cli.rb
```
