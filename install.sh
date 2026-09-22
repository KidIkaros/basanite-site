#!/usr/bin/env bash
# basanite installer — three modes, auto-selected:
#   1. binary download from the public basanite-site releases (fast path)
#   2. build from source (fallback: requires cargo + access to the source repos)
#   3. --prefix / --build-from-source for explicit control
# The product proving self-sovereignty installs without a server round-trip
# beyond the download itself. SHA256 verified when checksums are present.
set -euo pipefail

# Binaries publish on the PUBLIC site repo (the product repo is private).
RELEASES_REPO="KidIkaros/basanite-site"
SOURCE_REPO="KidIkaros/basanite"
BIN="basanite"
VERSION="${VERSION:-latest}"
PREFIX="${PREFIX:-$HOME/.local}"

say() { printf '%s\n' "$*"; }

INSTALL_DIR="$PREFIX/bin"
mkdir -p "$INSTALL_DIR"

finish() {
  say "==> installed: $INSTALL_DIR/$BIN"
  case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *) say "    note: $INSTALL_DIR is not in your PATH"
       say "    add it:  export PATH=\"$INSTALL_DIR:\$PATH\"" ;;
  esac
  say "==> try it:  $BIN --help"
}

build_from_source() {
  command -v cargo >/dev/null 2>&1 || {
    say "error: no prebuilt binary for ${OS}-${ARCH} and cargo is not installed."
    say "install rust from https://rustup.rs then re-run this script"
    exit 1
  }
  say "==> building basanite from source (release)…"
  TMP="$(mktemp -d)"
  git clone --depth 1 "https://github.com/$SOURCE_REPO" "$TMP/src"
  (cd "$TMP/src" && cargo build --release)
  cp "$TMP/src/target/release/$BIN" "$INSTALL_DIR/$BIN"
  rm -rf "$TMP"
}

# ─── explicit modes ────────────────────────────────────────────
case "${1:-}" in
  --prefix)
    [ -n "${2:-}" ] || { say "usage: install.sh --prefix /usr/local"; exit 2; }
    PREFIX="$2"; INSTALL_DIR="$PREFIX/bin"; mkdir -p "$INSTALL_DIR" ;;
  --build-from-source)
    build_from_source; finish; exit 0 ;;
esac

# ─── detect platform ───────────────────────────────────────────
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)  ARCH="x86_64" ;;
  aarch64|arm64) ARCH="aarch64" ;;
  *) say "no prebuilt binary for $ARCH — building from source"; build_from_source; finish; exit 0 ;;
esac
[ "$OS" = "linux" ] || [ "$OS" = "darwin" ] || {
  say "no prebuilt binary for $OS — building from source"; build_from_source; finish; exit 0; }

# ─── resolve version ───────────────────────────────────────────
if [ "$VERSION" = "latest" ]; then
  VERSION="$(curl -sfL "https://api.github.com/repos/$RELEASES_REPO/releases/latest" \
    | grep '"tag_name"' | head -1 | cut -d'"' -f4)" || VERSION=""
  [ -n "$VERSION" ] || { say "no releases yet — building from source"; build_from_source; finish; exit 0; }
fi

# ─── download & verify ─────────────────────────────────────────
TARBALL="basanite-${VERSION}-${OS}-${ARCH}.tar.gz"
BASE="https://github.com/$RELEASES_REPO/releases/download/$VERSION"
say "==> downloading $TARBALL"
if ! curl -sfL "$BASE/$TARBALL" -o "/tmp/$TARBALL"; then
  say "download failed — building from source"; build_from_source; finish; exit 0
fi

if curl -sfL "$BASE/checksums.txt" -o /tmp/basanite-checksums.txt; then
  if (cd /tmp && sha256sum -c --ignore-missing basanite-checksums.txt); then
    say "==> checksum OK"
  else
    say "!! checksum MISMATCH — aborting (do not ignore this)"
    exit 1
  fi
fi

TMPX="$(mktemp -d)"
tar xzf "/tmp/$TARBALL" -C "$TMPX" --strip-components=1
cp "$TMPX/$BIN" "$INSTALL_DIR/$BIN"
chmod +x "$INSTALL_DIR/$BIN"
rm -rf "$TMPX" "/tmp/$TARBALL" /tmp/basanite-checksums.txt
finish
