#!/bin/sh
set -eu

# Thin curl bootstrap for the installer owned by the wand-agent package. The
# package CLI remains the single source of truth for Go selection, builds and
# systemd registration.

WAND_AGENT_REPOSITORY="${WAND_AGENT_REPOSITORY:-beforeugone520/wand-agent}"
WAND_AGENT_REF="${WAND_AGENT_REF:-main}"

fail() {
  printf 'wand-agent install: %s\n' "$*" >&2
  exit 1
}

command -v node >/dev/null 2>&1 ||
  fail 'Node.js 16 or newer is required; install Node.js, npm or pnpm first'

node_major="$(node -p "Number(process.versions.node.split('.')[0])" 2>/dev/null || printf '0')"
case "$node_major" in
  ''|*[!0-9]*) fail 'could not determine the Node.js version' ;;
esac
[ "$node_major" -ge 16 ] ||
  fail "Node.js 16 or newer is required (found $(node --version 2>/dev/null || printf unknown))"

command -v tar >/dev/null 2>&1 || fail '`tar` is required'

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/wand-agent-install.XXXXXX")" ||
  fail 'could not create a temporary directory'
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT HUP INT TERM

archive="$tmp_dir/wand-agent.tar.gz"
source_dir="$tmp_dir/source"
archive_url="https://api.github.com/repos/${WAND_AGENT_REPOSITORY}/tarball/${WAND_AGENT_REF}"

printf 'wand-agent install: downloading %s@%s\n' "$WAND_AGENT_REPOSITORY" "$WAND_AGENT_REF"
if command -v curl >/dev/null 2>&1; then
  curl -fL --retry 3 --connect-timeout 20 -o "$archive" "$archive_url"
elif command -v wget >/dev/null 2>&1; then
  wget --tries=3 --timeout=20 -O "$archive" "$archive_url"
else
  fail '`curl` or `wget` is required to download wand-agent'
fi

mkdir -p "$source_dir"
tar -xzf "$archive" --strip-components=1 -C "$source_dir"
[ -f "$source_dir/bin/wand-agent.js" ] || fail 'downloaded package is missing bin/wand-agent.js'

node "$source_dir/bin/wand-agent.js" service install "$@"
