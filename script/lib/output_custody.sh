#!/usr/bin/env bash

# Output-path custody helpers shared by the release staging scripts. These
# functions intentionally support macOS's system Bash 3.2.

clasp_custody_fail() {
  echo "output custody rejected: $*" >&2
  return 1
}

clasp_require_canonical_absolute_path() {
  local path="$1"
  local label="$2"

  if [[ "$path" != /* ]]; then
    clasp_custody_fail "$label must be an absolute path"
    return 1
  fi
  if [[ "$path" == *$'\n'* || "$path" == *$'\r'* ]]; then
    clasp_custody_fail "$label contains a line break"
    return 1
  fi
  if [[ "$path" == *//* ]]; then
    clasp_custody_fail "$label is not canonical: $path"
    return 1
  fi
  case "/${path#/}/" in
    */./*|*/../*)
      clasp_custody_fail "$label contains a path traversal segment: $path"
      return 1
      ;;
  esac
  return 0
}

clasp_require_physical_directory() {
  local directory="$1"
  local label="$2"
  local physical

  clasp_require_canonical_absolute_path "$directory" "$label" || return 1
  if [[ ! -d "$directory" || -L "$directory" ]]; then
    clasp_custody_fail "$label must be a plain directory: $directory"
    return 1
  fi
  physical="$(cd "$directory" && pwd -P)"
  if [[ "$physical" != "$directory" ]]; then
    clasp_custody_fail "$label contains a symbolic-link component: $directory"
    return 1
  fi
  return 0
}

clasp_prepare_plain_directory() {
  local directory="$1"
  local label="$2"
  local parent

  clasp_require_canonical_absolute_path "$directory" "$label" || return 1
  if [[ -L "$directory" ]]; then
    clasp_custody_fail "$label must not be a symbolic link: $directory"
    return 1
  fi
  if [[ ! -e "$directory" ]]; then
    parent="$(dirname "$directory")"
    clasp_require_physical_directory "$parent" "$label parent" || return 1
    mkdir "$directory" || return 1
  fi
  clasp_require_physical_directory "$directory" "$label" || return 1
  return 0
}

clasp_prepare_channel_output_root() {
  local repository_root="$1"
  local channel="$2"

  clasp_require_physical_directory "$repository_root" "repository root" || return 1
  case "$channel" in
    local)
      clasp_prepare_plain_directory "$repository_root/dist" "local output root" || return 1
      ;;
    direct)
      clasp_prepare_plain_directory "$repository_root/release-output" "direct output root" || return 1
      ;;
    app-store)
      clasp_prepare_plain_directory "$repository_root/release-output" "release output root" || return 1
      clasp_prepare_plain_directory "$repository_root/release-output/AppStore" "App Store output root" || return 1
      ;;
    *)
      clasp_custody_fail "unknown channel: $channel"
      return 1
      ;;
  esac
  return 0
}

clasp_compile_no_replace_mover() {
  local repository_root="$1"
  local output="$2"
  local compiler
  local sdk_root
  local source="$repository_root/script/lib/rename_no_replace.c"

  clasp_require_physical_directory "$repository_root" "repository root" || return 1
  if [[ ! -f "$source" || -L "$source" ]]; then
    clasp_custody_fail "exclusive-rename source is missing or unsafe: $source"
    return 1
  fi
  clasp_require_canonical_absolute_path "$output" "exclusive-rename helper output" || return 1
  if [[ -e "$output" || -L "$output" ]]; then
    clasp_custody_fail "exclusive-rename helper output already exists: $output"
    return 1
  fi
  clasp_require_physical_directory "$(dirname "$output")" "exclusive-rename helper parent" || return 1
  compiler="$(xcrun --find clang)" || return 1
  sdk_root="$(xcrun --sdk macosx --show-sdk-path)" || return 1
  "$compiler" -isysroot "$sdk_root" -Wall -Wextra -Werror -O2 "$source" -o "$output" || return 1
  [[ -x "$output" ]] || {
    clasp_custody_fail "exclusive-rename helper was not produced"
    return 1
  }
  return 0
}

clasp_require_fresh_named_output() {
  local output_root="$1"
  local output="$2"
  local expected_name="$3"
  local label="$4"

  clasp_require_physical_directory "$output_root" "$label root" || return 1
  clasp_require_canonical_absolute_path "$output" "$label" || return 1
  if [[ "$output" != "$output_root/$expected_name" ]]; then
    clasp_custody_fail "$label must be exactly $output_root/$expected_name"
    return 1
  fi
  if [[ -e "$output" || -L "$output" ]]; then
    clasp_custody_fail "refusing to overwrite existing $label: $output"
    return 1
  fi
  return 0
}

clasp_validate_app_store_wrapper_output() {
  local repository_root="$1"
  local app_name="$2"
  local output="$3"
  local managed_mode="$4"
  local output_root="$repository_root/release-output/AppStore"
  local expected="$output_root/$app_name.app"
  local parent parent_name

  clasp_require_canonical_absolute_path "$output" "App Store wrapper output" || return 1
  if [[ "$(basename "$output")" != "$app_name.app" ]]; then
    clasp_custody_fail "App Store wrapper output must be named $app_name.app"
    return 1
  fi
  parent="$(dirname "$output")"
  clasp_require_physical_directory "$parent" "App Store wrapper output parent" || return 1
  if [[ -z "$managed_mode" ]]; then
    if [[ "$output" != "$expected" ]]; then
      clasp_custody_fail "App Store wrapper output must be exactly $expected"
      return 1
    fi
  elif [[ "$managed_mode" == app-store-package ]]; then
    parent_name="$(basename "$parent")"
    if [[ "$(dirname "$parent")" != "$output_root" || "$parent_name" != .clasp-package.* ]]; then
      clasp_custody_fail "managed App Store wrapper output escaped its package staging directory"
      return 1
    fi
  else
    clasp_custody_fail "invalid App Store wrapper managed mode: $managed_mode"
    return 1
  fi
  if [[ -e "$output" || -L "$output" ]]; then
    clasp_custody_fail "refusing to overwrite existing App Store wrapper output: $output"
    return 1
  fi
  return 0
}

clasp_validate_stage_output() {
  local repository_root="$1"
  local app_name="$2"
  local channel="$3"
  local output="$4"
  local managed_mode="$5"
  local replace_local="$6"
  local output_root expected parent parent_name grandparent grandparent_name

  clasp_require_canonical_absolute_path "$output" "staged app output" || return 1
  if [[ "$(basename "$output")" != "$app_name.app" ]]; then
    clasp_custody_fail "staged app output must be named $app_name.app"
    return 1
  fi
  parent="$(dirname "$output")"
  clasp_require_physical_directory "$parent" "staged app output parent" || return 1

  case "$channel" in
    local)
      output_root="$repository_root/dist"
      expected="$output_root/$app_name.app"
      if [[ -n "$managed_mode" ]]; then
        clasp_custody_fail "the local channel does not accept managed release output"
        return 1
      fi
      if [[ "$output" != "$expected" ]]; then
        clasp_custody_fail "local staged output must be exactly $expected"
        return 1
      fi
      ;;
    direct)
      output_root="$repository_root/release-output"
      expected="$output_root/$app_name.app"
      if [[ -z "$managed_mode" ]]; then
        if [[ "$output" != "$expected" ]]; then
          clasp_custody_fail "direct staged output must be exactly $expected"
          return 1
        fi
      elif [[ "$managed_mode" == direct-package ]]; then
        parent_name="$(basename "$parent")"
        if [[ "$(dirname "$parent")" != "$output_root" || "$parent_name" != .clasp-direct-package.* ]]; then
          clasp_custody_fail "managed direct output escaped its package staging directory"
          return 1
        fi
      else
        clasp_custody_fail "invalid managed output mode for the direct channel: $managed_mode"
        return 1
      fi
      if ((replace_local != 0)); then
        clasp_custody_fail "direct output can never replace an existing artifact"
        return 1
      fi
      ;;
    app-store)
      output_root="$repository_root/release-output/AppStore"
      expected="$output_root/$app_name.app"
      if [[ -z "$managed_mode" ]]; then
        if [[ "$output" != "$expected" ]]; then
          clasp_custody_fail "App Store staged output must be exactly $expected"
          return 1
        fi
      elif [[ "$managed_mode" == app-store ]]; then
        parent_name="$(basename "$parent")"
        grandparent="$(dirname "$parent")"
        grandparent_name="$(basename "$grandparent")"
        if [[ "$grandparent" == "$output_root" ]]; then
          if [[ "$parent_name" != .clasp-app-store.* ]]; then
            clasp_custody_fail "managed App Store output has an unexpected staging directory"
            return 1
          fi
        else
          if [[ "$(dirname "$grandparent")" != "$output_root" \
            || "$grandparent_name" != .clasp-package.* \
            || "$parent_name" != .clasp-app-store.* ]]; then
            clasp_custody_fail "managed App Store output escaped its package staging directories"
            return 1
          fi
        fi
      else
        clasp_custody_fail "invalid managed output mode for the App Store channel: $managed_mode"
        return 1
      fi
      if ((replace_local != 0)); then
        clasp_custody_fail "App Store output can never replace an existing artifact"
        return 1
      fi
      ;;
    *)
      clasp_custody_fail "unknown channel: $channel"
      return 1
      ;;
  esac

  if [[ -e "$output" || -L "$output" ]]; then
    if [[ "$channel" == local && "$replace_local" == 1 && -d "$output" && ! -L "$output" ]]; then
      return 0
    fi
    clasp_custody_fail "refusing to overwrite existing staged app output: $output"
    return 1
  fi
  return 0
}
