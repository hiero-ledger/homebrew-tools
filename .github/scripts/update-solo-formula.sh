#!/usr/bin/env bash
#
# This script is used by the GitHub Actions workflow to bump the
# Homebrew Solo formula to a new version. It performs the following:
#   - Reads the current version from Formula/solo.rb
#   - Creates a pinned Formula/solo@<current_version>.rb
#   - Copies Formula/solo@0.48.0.rb to Formula/solo.rb
#   - Downloads the npm tarball for the new version and computes sha256
#   - Updates class name, description, url, version, and sha256 in solo.rb
#
set -euo pipefail

# Resolve NEW_VERSION from environment or first positional argument.
# This allows both:
#   NEW_VERSION=0.50.0 .github/scripts/update-solo-formula.sh
#   .github/scripts/update-solo-formula.sh 0.50.0
NEW_VERSION_ENV="${NEW_VERSION:-}"
NEW_VERSION_ARG="${1:-}"
NEW_VERSION_RAW="${NEW_VERSION_ARG:-$NEW_VERSION_ENV}"
NEW_VERSION="${NEW_VERSION_RAW//[[:space:]]/}"

if [[ -z "${NEW_VERSION}" ]]; then
  echo "Usage: NEW_VERSION=<version> $0 or $0 <version>" >&2
  exit 1
fi

# Directory and file locations for the formulae.
# FORMULA_DIR can be overridden from the environment to point somewhere else.
FORMULA_DIR="${FORMULA_DIR:-Formula}"
CURRENT_FORMULA="${FORMULA_DIR}/solo.rb"          # The current Homebrew formula.
TEMPLATE="${FORMULA_DIR}/solo@0.48.0.rb"          # Template used to generate the new version.

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
cp "${CURRENT_FORMULA}" "${VERSIONED_FORMULA}"
echo "Created pinned formula ${VERSIONED_FORMULA}"

# Build the new Formula/solo.rb from the fixed 0.48.0 template.
# We keep the structure from the template but swap out:
#   - Class suffix (SoloAT0480 -> SoloAT<NEW_SUFFIX>)
#   - Version in the description (v0.48.0 -> v<NEW_VERSION>)
#   - Tarball URL version segment
#   - version "..." field
#   - sha256 value
TEMPLATE_VERSION="0.48.0"
TEMPLATE_SUFFIX=$(echo "${TEMPLATE_VERSION}" | tr -d '.')
NEW_SUFFIX=$(echo "${NEW_VERSION}" | tr -d '.')

cp "${TEMPLATE}" "${CURRENT_FORMULA}"

# Download the npm tarball for the target version and compute its
# SHA-256 hash. This value is written into the formula's sha256 field.
NEW_URL="https://registry.npmjs.org/@hashgraph/solo/-/solo-${NEW_VERSION}.tgz"
echo "Downloading ${NEW_URL} to compute sha256..."
if command -v sha256sum >/dev/null 2>&1; then
  # Linux / GNU coreutils: use sha256sum
  NEW_SHA256=$(curl -sL "${NEW_URL}" | sha256sum | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  # macOS: use shasum -a 256
  NEW_SHA256=$(curl -sL "${NEW_URL}" | shasum -a 256 | awk '{print $1}')
else
  echo "Neither sha256sum nor shasum is available" >&2
  exit 1
fi

if [[ -z "${NEW_SHA256}" ]]; then
  echo "Failed to calculate sha256 for ${NEW_URL}" >&2
  exit 1
fi
echo "Computed sha256: ${NEW_SHA256}"

# Replace the various version-specific bits in the copied template:
#   - Class name suffix (SoloAT0480 -> SoloAT<NEW_SUFFIX>)
#   - Human-readable version in the description
#   - Tarball name in the url
#   - version "..." stanza
#   - sha256 line
sedi "s/SoloAT${TEMPLATE_SUFFIX}/SoloAT${NEW_SUFFIX}/g" "${CURRENT_FORMULA}"

# Replace version in desc (v0.48.0 -> vNEW_VERSION)
sedi "s/v${TEMPLATE_VERSION}/v${NEW_VERSION}/g" "${CURRENT_FORMULA}"

# Replace url tarball version
sedi "s/solo-${TEMPLATE_VERSION}\.tgz/solo-${NEW_VERSION}.tgz/g" "${CURRENT_FORMULA}"

# Replace version field
sedi "s/version \"${TEMPLATE_VERSION}\"/version \"${NEW_VERSION}\"/g" "${CURRENT_FORMULA}"

# Replace sha256 line
sedi "s/^  sha256 \".*\"$/  sha256 \"${NEW_SHA256}\"/" "${CURRENT_FORMULA}"

echo "Updated ${CURRENT_FORMULA} for version ${NEW_VERSION}"
