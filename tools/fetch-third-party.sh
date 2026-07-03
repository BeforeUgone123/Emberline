#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY_DIR="$ROOT_DIR/third_party"
CACHE_ROOT="${HMG_THIRD_PARTY_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/hmg-third-party}"
mkdir -p "$THIRD_PARTY_DIR" "$CACHE_ROOT"

export_source() {
  local url="$1"
  local ref="$2"
  local name="$3"
  local cache_dir="$CACHE_ROOT/$name"
  local output_dir="$THIRD_PARTY_DIR/$name"

  if [[ -d "$cache_dir/.git" ]]; then
    git -C "$cache_dir" fetch --depth 1 origin "$ref"
    git -c advice.detachedHead=false -C "$cache_dir" checkout --detach --quiet FETCH_HEAD
  else
    git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$ref" "$url" "$cache_dir"
  fi
  git -C "$cache_dir" submodule update --init --recursive --depth 1

  rm -rf "$output_dir"
  mkdir -p "$output_dir"
  find "$cache_dir" -mindepth 1 -maxdepth 1 ! -name .git -exec cp -R {} "$output_dir/" \;
  printf '%s %s\n' "$url" "$ref" > "$output_dir/.source-version"
}

export_source "https://github.com/Mbed-TLS/mbedtls.git" "mbedtls-3.6.6" "mbedtls"
export_source "https://github.com/libssh2/libssh2.git" "libssh2-1.11.1" "libssh2"

echo "Native dependencies are ready under $THIRD_PARTY_DIR"
