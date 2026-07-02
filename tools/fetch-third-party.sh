#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY_DIR="$ROOT_DIR/third_party"
mkdir -p "$THIRD_PARTY_DIR"

clone_or_update() {
  local url="$1"
  local dir="$2"
  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" fetch --depth 1 origin
    git -C "$dir" reset --hard FETCH_HEAD
    return
  fi
  git clone --depth 1 "$url" "$dir"
}

clone_or_update "https://github.com/Mbed-TLS/mbedtls.git" "$THIRD_PARTY_DIR/mbedtls"
clone_or_update "https://github.com/libssh2/libssh2.git" "$THIRD_PARTY_DIR/libssh2"

echo "Native dependencies are ready under $THIRD_PARTY_DIR"

