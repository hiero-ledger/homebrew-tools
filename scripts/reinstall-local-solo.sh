#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ENV_HINTS=1

CURRENT_USER="$(id -un)"
TAP_NAME="${1:-$CURRENT_USER/tools}"
FORMULA_NAME="solo"
SOURCE_FORMULA="$SOURCE_REPO/Formula/$FORMULA_NAME.rb"

run_brew() {
  brew "$@"
}

CURRENT_ARCH="$(arch)"
BREW_PREFIX="$(run_brew --prefix)"

if [[ "$(uname -s)" == "Darwin" && "$BREW_PREFIX" == "/opt/homebrew" && "$CURRENT_ARCH" != "arm64" ]]; then
  echo "Detected Homebrew in /opt/homebrew while running under $CURRENT_ARCH. Re-running this script under arm64..."
  exec arch -arm64 /bin/bash "$0" "$@"
fi

if [[ ! -f "$SOURCE_FORMULA" ]]; then
  echo "ERROR: Source formula not found: $SOURCE_FORMULA" >&2
  exit 1
fi

if ! run_brew tap | grep -qx "$TAP_NAME"; then
  echo "Tap $TAP_NAME is not present. Adding custom remote tap from $SOURCE_REPO..."
  run_brew tap --custom-remote "$TAP_NAME" "file://$SOURCE_REPO"
fi

TAP_REPO="$(run_brew --repo "$TAP_NAME")"
TAP_FORMULA="$TAP_REPO/Formula/$FORMULA_NAME.rb"

mkdir -p "$(dirname "$TAP_FORMULA")"
cp "$SOURCE_FORMULA" "$TAP_FORMULA"

echo "Using tap formula: $TAP_FORMULA"
grep -n "link_overwrite" "$TAP_FORMULA" || {
  echo "WARNING: link_overwrite not found in tapped formula."
}

if run_brew tap | grep -qx "$TAP_NAME"; then
  echo "Tap repository: $(run_brew --repo "$TAP_NAME")"
fi

echo "Unlinking conflicting versioned solo formulae (if any)..."
while read -r installed_formula; do
  [[ -z "$installed_formula" ]] && continue
  if [[ "$installed_formula" == solo@* ]]; then
    run_brew unlink "$installed_formula" 2>/dev/null || true
  fi
done < <(run_brew list --formula 2>/dev/null || true)

if run_brew list --formula "$FORMULA_NAME" >/dev/null 2>&1; then
  echo "Reinstalling $TAP_NAME/$FORMULA_NAME from source..."
  run_brew reinstall --build-from-source "$TAP_NAME/$FORMULA_NAME"
else
  echo "Installing $TAP_NAME/$FORMULA_NAME from source..."
  run_brew install --build-from-source "$TAP_NAME/$FORMULA_NAME"
fi

echo
echo "Active solo version:"
solo --version || true
echo
echo "Symlink target:"
ls -l "$BREW_PREFIX/bin/solo" || true
