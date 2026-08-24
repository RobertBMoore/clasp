#!/usr/bin/env bash

# Installs the reviewed direct-channel SwiftPM lockfile without following or
# replacing an existing Package.resolved path. Callers must remove it through
# clasp_remove_direct_package_resolution so unexpected mutations are preserved
# and fail closed instead of being deleted.

clasp_direct_resolution_fail() {
  echo "direct Package.resolved custody failed: $*" >&2
  return 1
}

clasp_require_direct_package_resolution_absent() {
  local target="$1"
  [[ ! -e "$target" && ! -L "$target" ]] || {
    clasp_direct_resolution_fail "target already exists or is a symbolic link: $target"
    return 1
  }
}

clasp_verify_direct_package_resolution() {
  local target="$1"
  local reviewed="$2"

  [[ -f "$reviewed" && ! -L "$reviewed" ]] || {
    clasp_direct_resolution_fail "reviewed lockfile is missing or unsafe: $reviewed"
    return 1
  }
  [[ -f "$target" && ! -L "$target" ]] || {
    clasp_direct_resolution_fail "temporary lockfile is missing, non-regular, or a symbolic link: $target"
    return 1
  }
  cmp -s "$target" "$reviewed" || {
    clasp_direct_resolution_fail "temporary lockfile differs from the reviewed direct lockfile"
    return 1
  }
}

clasp_install_direct_package_resolution() {
  local target="$1"
  local reviewed="$2"
  local staged

  clasp_require_direct_package_resolution_absent "$target" || return 1
  [[ -f "$reviewed" && ! -L "$reviewed" ]] || {
    clasp_direct_resolution_fail "reviewed lockfile is missing or unsafe: $reviewed"
    return 1
  }

  staged="$(mktemp "${target}.clasp-install.XXXXXX")" || return 1
  if ! cp "$reviewed" "$staged" || ! chmod 0644 "$staged"; then
    rm -f "$staged"
    clasp_direct_resolution_fail "could not stage the reviewed lockfile"
    return 1
  fi

  # BSD mv -n never replaces a path that appeared after the absence check.
  # It may still return success when declining the move, so the staged-file
  # postcondition is the authoritative no-replace result.
  if ! mv -n "$staged" "$target"; then
    rm -f "$staged"
    clasp_direct_resolution_fail "could not install the reviewed lockfile"
    return 1
  fi
  if [[ -e "$staged" || -L "$staged" ]]; then
    rm -f "$staged"
    clasp_direct_resolution_fail "target appeared while installing the reviewed lockfile"
    return 1
  fi

  clasp_verify_direct_package_resolution "$target" "$reviewed" || {
    echo "preserving unexpected Package.resolved state: $target" >&2
    return 1
  }
}

clasp_remove_direct_package_resolution() {
  local target="$1"
  local reviewed="$2"

  clasp_verify_direct_package_resolution "$target" "$reviewed" || {
    echo "refusing to remove unexpected Package.resolved state: $target" >&2
    return 1
  }
  rm -f "$target" || {
    clasp_direct_resolution_fail "could not remove the owned temporary lockfile: $target"
    return 1
  }
  clasp_require_direct_package_resolution_absent "$target"
}
