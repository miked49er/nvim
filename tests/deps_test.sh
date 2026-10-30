#!/usr/bin/env bash
# Behavior tests for deps.sh with stubbed brew/uname. Run: bash tests/deps_test.sh
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0

setup() {
  T="$(mktemp -d)"; BIN="$T/bin"; mkdir -p "$BIN"
  : >"$T/installed"; : >"$T/brew.log"
  export T FAKE_UNAME="${FAKE_UNAME:-Darwin}" FAKE_BREW_FAIL=""
  cat >"$BIN/uname" <<'S'
#!/bin/sh
echo "$FAKE_UNAME"
S
  cat >"$BIN/brew" <<'S'
#!/bin/sh
# state: $T/installed holds one package name per line
case "$1" in
  list) shift; while [ "${1#--}" != "$1" ]; do shift; done
        grep -qx "$1" "$T/installed" ;;
  install) shift; while [ "${1#--}" != "$1" ]; do shift; done
        echo "install $1" >>"$T/brew.log"
        [ "$1" = "$FAKE_BREW_FAIL" ] && exit 1
        echo "$1" >>"$T/installed" ;;
esac
S
  chmod +x "$BIN/uname" "$BIN/brew"
  PATH_STUB="$BIN:/usr/bin:/bin"
}

run() { OUT="$(PATH="$PATH_STUB" bash "$ROOT/deps.sh" "$@" 2>&1)"; RC=$?; }
check() { # name, condition-result
  if [ "$2" = 0 ]; then echo "ok   - $1"; else echo "FAIL - $1"; echo "$OUT" | sed 's/^/       /'; fails=$((fails+1)); fi
}
has() { grep -q -- "$1" <<<"$OUT"; }
logged() { grep -q -- "$1" "$T/brew.log"; }

# 1. Fresh run installs required set; no extras
setup; run
check "fresh run exits 0" "$RC"
logged "install ripgrep"; check "installs ripgrep" $?
logged "install tree-sitter-cli"; check "installs tree-sitter-cli" $?
logged "install font-jetbrains-mono-nerd-font"; check "installs nerd font" $?
logged "install go"; r=$?; check "default run does not install go" $((r==0))

# 2. Re-run is idempotent
: >"$T/brew.log"; run
check "rerun exits 0" "$RC"
[ ! -s "$T/brew.log" ]; check "rerun installs nothing" $?
has "installed: 0"; check "rerun summary: installed 0" $?
has "failed: 0"; check "rerun summary: failed 0" $?

# 3. Missing node warns, does not fail or install
setup; run
has "WARN.*node.*nvm"; check "missing node warns with nvm pointer" $?
check "missing node still exits 0" "$RC"
logged "node"; r=$?; check "node never installed" $((r==0))

# 4. --with-extras installs optional toolchains
setup; run --with-extras
for p in go openjdk kotlin gradle groovy openscad docker; do
  logged "install $p"; check "--with-extras installs $p" $?
done

# 5. Failures are reported, run continues, exit 1
setup; FAKE_BREW_FAIL=ripgrep run
check "failure exits 1" $((RC==1 ? 0 : 1))
has "failed: 1"; check "failure counted" $?
logged "install tree-sitter-cli"; check "continues past failure" $?

# 6. Non-Darwin unsupported
setup; FAKE_UNAME=Linux run
check "non-Darwin exits 2" $((RC==2 ? 0 : 1))

# 7. Unknown flag
setup; run --bogus
check "unknown flag exits 2" $((RC==2 ? 0 : 1))

[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
