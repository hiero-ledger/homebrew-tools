#!/usr/bin/env bash
set -euo pipefail

# NEW_VERSION can be passed via env or as first argument
NEW_VERSION_ENV="${NEW_VERSION:-}"
NEW_VERSION_ARG="${1:-}"
NEW_VERSION_RAW="${NEW_VERSION_ARG:-$NEW_VERSION_ENV}"
NEW_VERSION="${NEW_VERSION_RAW//[[:space:]]/}"

if [[ -z "${NEW_VERSION}" ]]; then
  echo "Usage: NEW_VERSION=<version> $0 or $0 <version>" >&2
  exit 1
fi

FORMULA_DIR="${FORMULA_DIR:-Formula}"
CURRENT_FORMULA="${FORMULA_DIR}/solo.rb"
TEMPLATE="${FORMULA_DIR}/solo@0.48.0.rb"

if [[ ! -f "${CURRENT_FORMULA}" ]]; then
  echo "Missing ${CURRENT_FORMULA}" >&2
  exit 1
fi

if [[ ! -f "${TEMPLATE}" ]]; then
  echo "Missing template ${TEMPLATE}" >&2
  exit 1
fi

# Helper for in-place sed that works on macOS and Linux
sedi() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

# Determine current version from solo.rb
CURRENT_VERSION=$(grep -E '^[[:space:]]*version[[:space:]]+"' "${CURRENT_FORMULA}" | sed -E 's/^[[:space:]]*version[[:space:]]+"([^"]+)".*/\1/')
if [[ -z "${CURRENT_VERSION}" ]]; then
  echo "Could not parse current version from ${CURRENT_FORMULA}" >&2
  exit 1
fi

if [[ "${CURRENT_VERSION}" == "${NEW_VERSION}" ]]; then
  echo "New version ${NEW_VERSION} is the same as current version" >&2
  exit 1
fi

# Create pinned formula for current version
VERSIONED_FORMULA="${FORMULA_DIR}/solo@${CURRENT_VERSION}.rb"
if [[ -e "${VERSIONED_FORMULA}" ]]; then
  echo "Versioned formula already exists: ${VERSIONED_FORMULA}" >&2
  exit 1
fi
cp "${CURRENT_FORMULA}" "${VERSIONED_FORMULA}"
echo "Created pinned formula ${VERSIONED_FORMULA}"

# Build new solo.rb from 0.48.0 template
TEMPLATE_VERSION="0.48.0"
TEMPLATE_SUFFIX=$(echo "${TEMPLATE_VERSION}" | tr -d '.')
NEW_SUFFIX=$(echo "${NEW_VERSION}" | tr -d '.')

cp "${TEMPLATE}" "${CURRENT_FORMULA}"

NEW_URL="https://registry.npmjs.org/@hashgraph/solo/-/solo-${NEW_VERSION}.tgz"
echo "Downloading ${NEW_URL} to compute sha256..."
if command -v sha256sum >/dev/null 2>&1; then
  NEW_SHA256=$(curl -sL "${NEW_URL}" | sha256sum | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
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

# Replace class suffix
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
