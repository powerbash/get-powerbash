#!/usr/bin/env bash
#
# Round-trip test for the installer.
#
# Every case runs against a throwaway $HOME and a file:// URL, so nothing
# touches the machine running it and it needs no network. Run it directly:
#
#   tests/install-test.sh
#
# bash 3.2-safe: the installer's whole point is surviving stock macOS bash.

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLER="$REPO_ROOT/index.html"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/get-powerbash-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

FAILED=0
pass() { printf '  ok: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; FAILED=1; }

# A stand-in for the real powerbash.sh: the installer only checks that the
# download parses as bash and uses the __powerbash namespace.
FAKE_SCRIPT="$WORK/powerbash.sh"
cat > "$FAKE_SCRIPT" <<'EOF'
#!/usr/bin/env bash
POWERBASH_VERSION="0.0.0-test"
__powerbash() { :; }
powerbash() { echo "powerbash $POWERBASH_VERSION"; }
EOF

# Downloads fine, but is not powerbash. Two flavors, because the installer
# runs two different checks: HTML fails to parse as bash, while a valid shell
# script that simply isn't powerbash fails the namespace match.
BAD_SCRIPT="$WORK/notpowerbash.html"
echo '<html><head><title>captive portal</title></head></html>' > "$BAD_SCRIPT"

WRONG_SCRIPT="$WORK/someotherscript.sh"
printf '#!/usr/bin/env bash\necho "a perfectly valid script"\n' > "$WRONG_SCRIPT"

# Run the installer with a fresh $HOME. $1 = home dir, rest = installer args.
run_installer() {
  local home="$1"; shift
  HOME="$home" \
  POWERBASH_URL="file://$FAKE_SCRIPT" \
    bash "$INSTALLER" "$@" 2>&1
}

new_home() {
  local home="$WORK/home.$1"
  mkdir -p "$home"
  echo "$home"
}

# --- install into a plain ~/.bashrc ---------------------------------------

home="$(new_home bashrc)"
printf '# user bashrc\nexport EDITOR=vi\n' > "$home/.bashrc"
cp "$home/.bashrc" "$WORK/bashrc.original"

out="$(run_installer "$home")"
if [ -f "$home/.local/share/powerbash/powerbash.sh" ]; then
  pass "installs the script into ~/.local/share/powerbash"
else
  fail "script not installed: $out"
fi

if grep -Fq '# >>> powerbash >>>' "$home/.bashrc"; then
  pass "adds the marker block to ~/.bashrc"
else
  fail "no marker block in ~/.bashrc"
fi

# The installed script must actually load in a shell that reads .bashrc.
got="$(HOME="$home" bash -c '. "$HOME/.bashrc" >/dev/null 2>&1; powerbash' 2>&1)"
case "$got" in
  *"0.0.0-test"*) pass "a new shell sources the installed script" ;;
  *) fail "new shell did not load powerbash: $got" ;;
esac

# --- re-running is idempotent ---------------------------------------------

run_installer "$home" >/dev/null
count="$(grep -Fc '# >>> powerbash >>>' "$home/.bashrc")"
if [ "$count" -eq 1 ]; then
  pass "re-running does not duplicate the marker block"
else
  fail "marker block appears $count times after a second install"
fi

# --- uninstall restores the startup file ----------------------------------

out="$(run_installer "$home" uninstall)"
if [ -e "$home/.local/share/powerbash/powerbash.sh" ]; then
  fail "uninstall left the script behind: $out"
else
  pass "uninstall removes the script"
fi

if grep -Fq 'powerbash' "$home/.bashrc"; then
  fail "uninstall left powerbash lines in ~/.bashrc"
else
  pass "uninstall removes the marker block"
fi

if diff -q "$WORK/bashrc.original" "$home/.bashrc" >/dev/null 2>&1; then
  pass "the startup file is byte-identical to before the install"
else
  fail "the startup file differs from the original after install+uninstall:
$(diff "$WORK/bashrc.original" "$home/.bashrc" || true)"
fi

# --- a startup file that ends in blank lines keeps them -------------------

home="$(new_home trailing)"
printf '# user bashrc\nexport EDITOR=vi\n\n\n' > "$home/.bashrc"
cp "$home/.bashrc" "$WORK/trailing.original"

run_installer "$home" >/dev/null
run_installer "$home" uninstall >/dev/null
if diff -q "$WORK/trailing.original" "$home/.bashrc" >/dev/null 2>&1; then
  pass "trailing blank lines in the startup file survive a round trip"
else
  fail "trailing blank lines were eaten:
$(diff "$WORK/trailing.original" "$home/.bashrc" || true)"
fi

# --- ~/.bashrc.d gets a symlink, not an edit ------------------------------

home="$(new_home bashrcd)"
mkdir -p "$home/.bashrc.d"
printf '# user bashrc\n' > "$home/.bashrc"

run_installer "$home" >/dev/null
if [ -L "$home/.bashrc.d/powerbash.sh" ]; then
  pass "links into ~/.bashrc.d when it exists"
else
  fail "no symlink in ~/.bashrc.d"
fi
if grep -Fq 'powerbash' "$home/.bashrc"; then
  fail "edited ~/.bashrc even though ~/.bashrc.d exists"
else
  pass "leaves ~/.bashrc untouched when ~/.bashrc.d exists"
fi

run_installer "$home" uninstall >/dev/null
if [ -L "$home/.bashrc.d/powerbash.sh" ]; then
  fail "uninstall left the ~/.bashrc.d symlink"
else
  pass "uninstall removes the ~/.bashrc.d symlink"
fi

# --- a bad download is not installed --------------------------------------

home="$(new_home baddownload)"
printf '# user bashrc\n' > "$home/.bashrc"
out="$(HOME="$home" POWERBASH_URL="file://$BAD_SCRIPT" bash "$INSTALLER" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  fail "installer succeeded on a non-powerbash download"
else
  pass "rejects a download that is not powerbash.sh"
fi
if [ -e "$home/.local/share/powerbash/powerbash.sh" ]; then
  fail "installed a bad download anyway"
else
  pass "installs nothing when the download fails validation"
fi
if grep -Fq 'powerbash' "$home/.bashrc" 2>/dev/null; then
  fail "edited ~/.bashrc despite a failed download"
else
  pass "leaves ~/.bashrc alone when the download fails validation"
fi

# --- a valid shell script that is not powerbash is rejected ---------------

home="$(new_home wrongscript)"
printf '# user bashrc\n' > "$home/.bashrc"
out="$(HOME="$home" POWERBASH_URL="file://$WRONG_SCRIPT" bash "$INSTALLER" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  fail "installed a valid shell script that is not powerbash"
else
  pass "rejects a valid shell script that is not powerbash"
fi

# --- a missing URL fails cleanly ------------------------------------------

home="$(new_home missing)"
out="$(HOME="$home" POWERBASH_URL="file://$WORK/does-not-exist" bash "$INSTALLER" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  fail "installer succeeded with an unreachable URL"
else
  case "$out" in
    *"download failed"*) pass "reports a failed download and stops" ;;
    *) fail "unhelpful output for a failed download: $out" ;;
  esac
fi

# --- refuses to run as root -----------------------------------------------

# Shim `id` rather than actually becoming root.
shim="$WORK/shim"
mkdir -p "$shim"
cat > "$shim/id" <<'EOF'
#!/bin/sh
[ "$1" = "-u" ] && { echo 0; exit 0; }
exec /usr/bin/id "$@"
EOF
chmod +x "$shim/id"

home="$(new_home root)"
out="$(HOME="$home" PATH="$shim:$PATH" POWERBASH_URL="file://$FAKE_SCRIPT" \
  bash "$INSTALLER" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  fail "installer ran as root"
else
  case "$out" in
    *"refusing to install as root"*) pass "refuses to run as root" ;;
    *) fail "root refusal message missing: $out" ;;
  esac
fi
case "$out" in
  *"/etc/profile.d/z_powerbash.sh"*) pass "points root at the manual install" ;;
  *) fail "root refusal does not mention the manual alternative" ;;
esac
if [ -e "$home/.local/share/powerbash/powerbash.sh" ]; then
  fail "installed something despite refusing to run as root"
else
  pass "installs nothing when refusing to run as root"
fi

# --- unknown arguments ----------------------------------------------------

home="$(new_home badarg)"
if HOME="$home" POWERBASH_URL="file://$FAKE_SCRIPT" bash "$INSTALLER" bogus >/dev/null 2>&1; then
  fail "accepted an unknown subcommand"
else
  pass "rejects an unknown subcommand"
fi

# --- uninstalling a clean machine is not an error -------------------------

home="$(new_home clean)"
out="$(run_installer "$home" uninstall)"
case "$out" in
  *"does not appear to be installed"*) pass "uninstall on a clean machine says so" ;;
  *) fail "unexpected uninstall output on a clean machine: $out" ;;
esac

echo
if [ "$FAILED" -eq 0 ]; then
  echo "all checks passed (bash $BASH_VERSION on $(uname -s))"
else
  echo "there were failures" >&2
fi
exit "$FAILED"
