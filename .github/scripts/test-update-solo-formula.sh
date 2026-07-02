#!/usr/bin/env bash
# Unit tests for update-solo-formula.sh
# Runs in a temp dir so the real Formula/ tree is never touched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATE_SCRIPT="${SCRIPT_DIR}/update-solo-formula.sh"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

assert_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -qE "${pattern}" "${file}" 2>/dev/null; then
    pass "${label}"
  else
    fail "${label} — pattern '${pattern}' not found in ${file}"
  fi
}

assert_not_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -qE "${pattern}" "${file}" 2>/dev/null; then
    fail "${label} — pattern '${pattern}' should NOT appear in ${file}"
  else
    pass "${label}"
  fi
}

assert_file_exists() {
  local file="$1" label="$2"
  if [[ -f "${file}" ]]; then
    pass "${label}"
  else
    fail "${label} — file not found: ${file}"
  fi
}

# --- Set up a temp test environment ---

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_TEST}"' EXIT

FORMULA_DIR="${TMPDIR_TEST}/Formula"
mkdir -p "${FORMULA_DIR}"

# Create a fake solo.rb at version 0.80.0
cat > "${FORMULA_DIR}/solo.rb" <<'RUBY'
class Solo < Formula
  desc "An opinionated CLI tool to deploy and manage standalone test networks."
  homepage "https://github.com/hiero-ledger/solo"

  url "https://registry.npmjs.org/@hiero-ledger/solo/-/solo-0.80.0.tgz"
  sha256 "aabbccdd"
  version "0.80.0"
  license "Apache-2.0"
  bottle :unneeded

  def install
    ohai "Pre-pulling default Solo cache images..."
    opoo "Could not pre-pull Solo cache images during install."
  end

  test do
    assert_match(/Usage/, shell_output("#{bin}/solo --help"))
  end
end
RUBY

# Create a fake solo.template.rb
cat > "${FORMULA_DIR}/solo.template.rb" <<'RUBY'
class Solo < Formula
  desc "An opinionated CLI tool to deploy and manage standalone test networks."
  homepage "https://github.com/hiero-ledger/solo"

  url "https://registry.npmjs.org/@hiero-ledger/solo/-/solo-__SOLO_VERSION__.tgz"
  sha256 "__SOLO_SHA256__"
  version "__SOLO_VERSION__"
  license "Apache-2.0"
  bottle :unneeded

  def install
    ohai "Pre-pulling default Solo cache images..."
    opoo "Could not pre-pull Solo cache images during install."
  end

  test do
    assert_match(/Usage/, shell_output("#{bin}/solo --help"))
    assert_match version.to_s, shell_output("#{bin}/solo --version 2>&1")
  end
end
RUBY

# Stub curl and sha256sum so the script never touches the network
STUB_BIN="${TMPDIR_TEST}/stub_bin"
mkdir -p "${STUB_BIN}"
cat > "${STUB_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
echo "fake-tarball-content"
EOF
chmod +x "${STUB_BIN}/curl"

cat > "${STUB_BIN}/sha256sum" <<'EOF'
#!/usr/bin/env bash
echo "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef  -"
EOF
chmod +x "${STUB_BIN}/sha256sum"

# --- Run the update script ---

FORMULA_DIR="${FORMULA_DIR}" \
  PATH="${STUB_BIN}:${PATH}" \
  bash "${UPDATE_SCRIPT}" 0.99.0

# --- Assertions ---

VERSIONED="${FORMULA_DIR}/solo@0.80.0.rb"
CURRENT="${FORMULA_DIR}/solo.rb"

assert_file_exists "${VERSIONED}" "versioned formula created"
assert_file_exists "${CURRENT}" "solo.rb still exists"

# Class rename: first line of versioned file
first_line="$(head -n 1 "${VERSIONED}")"
if [[ "${first_line}" == "class SoloAT0800 < Formula" ]]; then
  pass "class line renamed correctly"
else
  fail "class line should be 'class SoloAT0800 < Formula', got: ${first_line}"
fi

# String corruption check: "SoloAT0800" must appear ONLY on the class declaration line
sole_count=$(grep -cE "SoloAT0800" "${VERSIONED}" || true)
if [[ "${sole_count}" -eq 1 ]]; then
  pass "SoloAT0800 appears exactly once (class line only)"
else
  fail "SoloAT0800 appears ${sole_count} times — string corruption detected"
fi

# User-facing strings must NOT be corrupted
assert_not_contains "${VERSIONED}" "SoloAT0800 cache images" "ohai message not corrupted"
assert_not_contains "${VERSIONED}" "pre-pull SoloAT0800" "opoo message not corrupted"

# solo.rb should have the new version substituted
assert_contains "${CURRENT}" "0\.99\.0" "solo.rb has new version"
assert_not_contains "${CURRENT}" "__SOLO_VERSION__" "solo.rb placeholders replaced"
assert_not_contains "${CURRENT}" "__SOLO_SHA256__" "solo.rb sha256 placeholder replaced"

# solo.rb should have the mock SHA
assert_contains "${CURRENT}" "deadbeef" "solo.rb has computed sha256"

# --- Summary ---

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "${FAIL}" -gt 0 ]]; then
  exit 1
fi
