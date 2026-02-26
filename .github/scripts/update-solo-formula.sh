#!/usr/bin/env bash
#
# This script is used by the GitHub Actions workflow to bump the
# Homebrew Solo formula to a new version. It performs the following:
#   - Reads the current version from Formula/solo.rb
#   - Creates a pinned Formula/solo@<current_version>.rb
#   - Renders Formula/solo.rb from Formula/solo.template.rb
#   - Downloads the npm tarball for the new version and computes sha256
#   - Updates url/version/sha256 placeholders in solo.rb
#
set -euo pipefail

# Resolve NEW_VERSION from environment or first positional argument.
# This allows both:
#   NEW_VERSION=0.50.0 .github/scripts/update-solo-formula.sh
#   .github/scripts/update-solo-formula.sh 0.50.0
NEW_VERSION_ENV="${NEW_VERSION:-}"
NEW_VERSION_ARG="${1:-}"
NEW_VERSION_RAW="${NEW_VERSION_ARG:-$NEW_VERSION_ENV}"
NEW_VERSION_INPUT="${NEW_VERSION_RAW//[[:space:]]/}"

# Normalize versions to strict x.y.z form so npm tarball URLs are valid.
# Examples:
#   0.58   -> 0.58.0
#   v0.58  -> 0.58.0
#   0.58.0 -> 0.58.0
normalize_semver() {
  local raw="${1#v}"
  if [[ "${raw}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "${raw}"
  elif [[ "${raw}" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "${raw}.0"
  else
    echo ""
  fi
}

NEW_VERSION="$(normalize_semver "${NEW_VERSION_INPUT}")"

if [[ -z "${NEW_VERSION}" ]]; then
  echo "Usage: NEW_VERSION=<x.y.z|x.y|vX.Y.Z> $0 or $0 <version>" >&2
  exit 1
fi

# Directory and file locations for the formulae.
# FORMULA_DIR can be overridden from the environment to point somewhere else.
FORMULA_DIR="${FORMULA_DIR:-Formula}"
CURRENT_FORMULA="${FORMULA_DIR}/solo.rb"          # The current Homebrew formula.
TEMPLATE="${FORMULA_DIR}/solo.template.rb"        # Template used to generate the new version.

# Sanity checks to ensure the required formula files exist before proceeding.
if [[ ! -f "${CURRENT_FORMULA}" ]]; then
  echo "Missing ${CURRENT_FORMULA}" >&2
  exit 1
fi

if [[ ! -f "${TEMPLATE}" ]]; then
  echo "Missing template ${TEMPLATE}" >&2
  exit 1
fi

# Guard against trying to "re-release" a version that already has a
# pinned formula. If Formula/solo@<NEW_VERSION>.rb exists, treat that
# as an indication that the target version already exists and abort.
TARGET_PINNED="${FORMULA_DIR}/solo@${NEW_VERSION}.rb"
if [[ -e "${TARGET_PINNED}" ]]; then
  echo "Pinned formula for target version already exists: ${TARGET_PINNED}" >&2
  exit 1
fi

# Helper for in-place sed that works on both GNU (Linux) and BSD (macOS).
# GNU sed accepts `-i` with no argument, while BSD sed (macOS) requires
# an explicit backup suffix, which we set to the empty string.
sedi() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

# Determine the current version from Formula/solo.rb by parsing the
# `version "x.y.z"` line. This is used to:
#   - Guard against bumping to the same version.
#   - Name the pinned formula file solo@<current_version>.rb.
CURRENT_VERSION=$(grep -E '^[[:space:]]*version[[:space:]]+"' "${CURRENT_FORMULA}" | sed -E 's/^[[:space:]]*version[[:space:]]+"([^"]+)".*/\1/')
if [[ -z "${CURRENT_VERSION}" ]]; then
  echo "Could not parse current version from ${CURRENT_FORMULA}" >&2
  exit 1
fi

if [[ "${CURRENT_VERSION}" == "${NEW_VERSION}" ]]; then
  echo "New version ${NEW_VERSION} is the same as current version" >&2
  exit 1
fi

# Create a pinned formula for the current version so users can
# continue to install that specific release as Formula/solo@<version>.
VERSIONED_FORMULA="${FORMULA_DIR}/solo@${CURRENT_VERSION}.rb"
if [[ -e "${VERSIONED_FORMULA}" ]]; then
  echo "Versioned formula already exists: ${VERSIONED_FORMULA}" >&2
  exit 1
fi

echo "CURRENT_FORMULA = ${CURRENT_FORMULA}"
echo "CURRENT_VERSION = ${CURRENT_VERSION}"

# Compute suffix for the current version (remove dots for class name)
CURRENT_SUFFIX=$(echo "${CURRENT_VERSION}" | tr -d '.')

# Copy previous latest one to a pinned version one.
# Class name suffix (Solo -> SoloAT${CURRENT_SUFFIX}).
cp "${CURRENT_FORMULA}" "${VERSIONED_FORMULA}"
sedi "s/Solo/SoloAT${CURRENT_SUFFIX}/g" "${VERSIONED_FORMULA}"

echo "Created pinned formula ${VERSIONED_FORMULA}"

# Build the new Formula/solo.rb from the dedicated template.
cp "${TEMPLATE}" "${CURRENT_FORMULA}"

# Download the npm tarball for the target version and compute its
# SHA-256 hash. This value is written into the formula's sha256 field.
NEW_URL="https://registry.npmjs.org/@hashgraph/solo/-/solo-${NEW_VERSION}.tgz"
echo "Downloading ${NEW_URL} to compute sha256..."
if command -v sha256sum >/dev/null 2>&1; then
  # Linux / GNU coreutils: use sha256sum
  NEW_SHA256=$(curl -fsSL "${NEW_URL}" | sha256sum | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  # macOS: use shasum -a 256
  NEW_SHA256=$(curl -fsSL "${NEW_URL}" | shasum -a 256 | awk '{print $1}')
else
  echo "Neither sha256sum nor shasum is available" >&2
  exit 1
fi

if [[ -z "${NEW_SHA256}" ]]; then
  echo "Failed to calculate sha256 for ${NEW_URL}" >&2
  exit 1
fi
echo "Computed sha256: ${NEW_SHA256}"

# Replace template placeholders.
sedi "s/__SOLO_VERSION__/${NEW_VERSION}/g" "${CURRENT_FORMULA}"
sedi "s/__SOLO_SHA256__/${NEW_SHA256}/g" "${CURRENT_FORMULA}"

echo "Updated ${CURRENT_FORMULA} for version ${NEW_VERSION}"
