#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY_DIR="$ROOT_DIR/third_party"
CACHE_ROOT="${HMG_THIRD_PARTY_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/hmg-third-party}"
mkdir -p "$THIRD_PARTY_DIR" "$CACHE_ROOT"

# export_source <git-url> <ref> <name> [shallow_since]
# <ref> may be a tag (mbedtls) or a full commit SHA (libssh2, see below): tags
# resolve through refs/tags/, while raw commit SHAs are fetched directly
# (GitHub allows reachable-SHA wants). Both land in FETCH_HEAD.
export_source() {
  local url="$1"
  local ref="$2"
  local name="$3"
  local since="${4:-}"
  local cache_dir="$CACHE_ROOT/$name"
  local output_dir="$THIRD_PARTY_DIR/$name"
  local depth_args=(--depth 1)
  if [[ -n "$since" ]]; then
    depth_args=("--shallow-since=$since")
  fi

  if [[ ! -d "$cache_dir/.git" ]]; then
    rm -rf "$cache_dir"
    git init --quiet -b master "$cache_dir"
    git -C "$cache_dir" remote add origin "$url"
  fi
  if [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
    git -C "$cache_dir" fetch --quiet "${depth_args[@]}" origin "$ref"
  elif ! git -C "$cache_dir" fetch --quiet "${depth_args[@]}" origin "refs/tags/$ref"; then
    git -C "$cache_dir" fetch --quiet "${depth_args[@]}" origin "$ref"
  fi
  git -c advice.detachedHead=false -C "$cache_dir" checkout --detach --quiet FETCH_HEAD
  git -C "$cache_dir" submodule update --init --recursive --depth 1

  rm -rf "$output_dir"
  mkdir -p "$output_dir"
  find "$cache_dir" -mindepth 1 -maxdepth 1 ! -name .git -exec cp -R {} "$output_dir/" \;
  printf '%s %s %s\n' "$url" "$ref" "$(git -C "$cache_dir" rev-parse HEAD)" > "$output_dir/.source-version"
}

export_source "https://github.com/Mbed-TLS/mbedtls.git" "mbedtls-3.6.6" "mbedtls"

# --- libssh2: pinned to a verified master commit (code review CR-001) --------
# As of 2026-08-14 there is NO libssh2 release containing the security fixes:
# the latest release remains 1.11.1 (2024-10-16), which OSV lists as affected
# by CVE-2026-55200 and CVE-2026-55199. We therefore pin the immutable master
# commit 4f271a3b8ebbcf204443d456210a6d6568682f6c (2026-08-14, signed by the
# maintainer) instead of a movable tag, and prove below via merge-base that the
# pinned tree contains every fix applicable to our handshake/transport/
# channel/SFTP usage:
#   97acf3df  CVE-2026-55200   pre-auth OOB write in ssh2_transport_read()
#                              (packet_length bounds; PR #2052)
#   17626857  CVE-2026-55199   pre-auth DoS in the SSH_MSG_EXT_INFO parser
#                              (packet.c; PR #1864)
#   42e33d81  CVE-2026-66035 / GHSA-6c79-444r-wx26
#                              heap overflow on ETM decrypt (PR #2198)
# The pin also carries the July 2026 transport/packet hardening our nonblocking
# read/write paths can hit (2877fa64/12a8bda8 crypt error translation,
# 823a2286 payload double-free, bf7fa4c1 EAGAIN UAF, 0a17ea04 GHSA-53q9-wmqr-
# fh7c). Not applicable to our call set: CVE-2025-15661 (sftp_symlink; never
# called) and CVE-2026-66034 (publickey subsystem; never called). The fetch
# keeps history since 2026-04-01 so merge-base can verify ancestry.
# Revisit once upstream cuts a release containing these fixes.
LIBSSH2_PIN="4f271a3b8ebbcf204443d456210a6d6568682f6c"
LIBSSH2_REQUIRED_FIXES=(
  "97acf3dfda80c91c3a8c9f2372546301d4a1a7a8"  # CVE-2026-55200
  "17626857d20b3c9a1addfa45979dadcee1cd84a4"  # CVE-2026-55199
  "42e33d81577ed4b95d4b4f6f845e5ee8efe5eeb4"  # CVE-2026-66035 / GHSA-6c79-444r-wx26
)
export_source "https://github.com/libssh2/libssh2.git" "$LIBSSH2_PIN" "libssh2" "2026-04-01"

libssh2_head="$(git -C "$CACHE_ROOT/libssh2" rev-parse HEAD)"
if [[ "$libssh2_head" != "$LIBSSH2_PIN" ]]; then
  echo "ERROR: libssh2 checkout moved unexpectedly: $libssh2_head != $LIBSSH2_PIN" >&2
  exit 1
fi
for fix in "${LIBSSH2_REQUIRED_FIXES[@]}"; do
  if ! git -C "$CACHE_ROOT/libssh2" merge-base --is-ancestor "$fix" HEAD; then
    echo "ERROR: pinned libssh2 $LIBSSH2_PIN misses required security fix $fix" >&2
    exit 1
  fi
done

echo "Native dependencies are ready under $THIRD_PARTY_DIR"
