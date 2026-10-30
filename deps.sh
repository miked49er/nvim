#!/usr/bin/env bash
# Install the external dependencies for this nvim config.
# Usage: deps.sh [--with-extras]
# Exit codes: 0 ok (warnings allowed), 1 one or more installs failed,
#             2 usage error or unsupported OS.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WITH_EXTRAS=0
for arg in "$@"; do
  case "$arg" in
    --with-extras) WITH_EXTRAS=1 ;;
    -h|--help) sed -n '2,5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "deps.sh: unknown option: $arg" >&2; exit 2 ;;
  esac
done

installed=(); skipped=(); failed=()

# install_brewfile FILE: for each `brew "x"` / `cask "x"` line, skip if present.
install_brewfile() {
  local kind name flag
  while read -r kind name _; do
    case "$kind" in brew|cask) ;; *) continue ;; esac
    name="${name//\"/}"
    flag="--formula"; [ "$kind" = cask ] && flag="--cask"
    if brew list "$flag" "$name" >/dev/null 2>&1; then
      skipped+=("$name"); echo "skip    $name"
    elif brew install "$flag" "$name"; then
      installed+=("$name"); echo "install $name"
    else
      failed+=("$name"); echo "FAILED  $name"
    fi
  done <"$1"
}

# Tools that ship with macOS / Xcode CLT: check only.
check_system_tools() {
  local t
  for t in cc make curl unzip tar gzip; do
    if command -v "$t" >/dev/null 2>&1; then
      skipped+=("$t"); echo "skip    $t (system)"
    else
      failed+=("$t"); echo "FAILED  $t missing (try: xcode-select --install)"
    fi
  done
}

check_node() {
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    echo "skip    node/npm"
  else
    echo "WARN: node/npm not found. Mason needs them for some servers; install via nvm: https://github.com/nvm-sh/nvm"
  fi
}

darwin() {
  if ! command -v brew >/dev/null 2>&1; then
    echo "deps.sh: Homebrew not found: https://brew.sh" >&2; exit 2
  fi
  check_system_tools
  install_brewfile "$DIR/Brewfile"
  [ "$WITH_EXTRAS" = 1 ] && install_brewfile "$DIR/Brewfile.extras"
  check_node
}

case "$(uname)" in
  Darwin) darwin ;;
  *) echo "deps.sh: unsupported OS: $(uname) (only Darwin is implemented)" >&2; exit 2 ;;
esac

echo
echo "Summary"
echo "  installed: ${#installed[@]} ${installed[*]:-}"
echo "  skipped: ${#skipped[@]}"
echo "  failed: ${#failed[@]} ${failed[*]:-}"
[ "${#failed[@]}" -eq 0 ]
