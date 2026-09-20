#!/bin/sh
#
# Update the Barrier server on the MacBook: pull, rebuild, reinstall, restart.
#
#     ./update-macos.sh
#     ./update-macos.sh --no-pull     rebuild what is already checked out
#
# Your certificate and trusted fingerprints live in
# ~/Library/Application Support/barrier/SSL and are untouched, so updating never
# means redoing the fingerprint exchange.

set -e

BRANCH="security-hardening"
# Overridable so the script can be exercised without writing to /Applications.
APP="${BARRIER_APP_PATH:-/Applications/Barrier.app}"
PULL=1

for arg in "$@"; do
    case "$arg" in
        --no-pull) PULL=0 ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^#//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 1 ;;
    esac
done

cd "$(dirname "$0")"

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# --- 1. pull -----------------------------------------------------------------
if [ "$PULL" -eq 1 ]; then
    say "Pulling $BRANCH"

    if [ -n "$(git status --porcelain)" ]; then
        warn "You have local changes:"
        git status --short | sed 's/^/    /'
        warn "Commit or stash them first, or run with --no-pull to skip pulling."
        die "refusing to pull over local changes"
    fi

    git checkout "$BRANCH"
    git pull --ff-only
    git submodule update --init --recursive
else
    say "Skipping pull (--no-pull)"
fi

# --- 2. build ----------------------------------------------------------------
say "Building"

QT_PREFIX="$(brew --prefix qt@5 2>/dev/null || true)"
SSL_PREFIX="$(brew --prefix openssl@3 2>/dev/null || true)"
[ -d "$QT_PREFIX" ]  || die "qt@5 not installed. Run: brew install qt@5"
[ -d "$SSL_PREFIX" ] || die "openssl@3 not installed. Run: brew install openssl@3"

cmake -S . -B build \
    -DCMAKE_PREFIX_PATH="$QT_PREFIX;$SSL_PREFIX" \
    -DBARRIER_BUILD_INSTALLER=ON \
    -DBARRIER_BUILD_TESTS=OFF \
    -DCMAKE_BUILD_TYPE=Release >/dev/null

cmake --build build -j"$(sysctl -n hw.ncpu)"

[ -d "build/bundle/Barrier.app" ] || die "build finished but build/bundle/Barrier.app is missing"

# --- 3. install --------------------------------------------------------------
say "Installing"

WAS_RUNNING=0
if pgrep -x barriers >/dev/null 2>&1 || pgrep -x barrier >/dev/null 2>&1; then
    WAS_RUNNING=1
fi

osascript -e 'quit app "Barrier"' >/dev/null 2>&1 || true
pkill -x barriers >/dev/null 2>&1 || true
pkill -x barrier  >/dev/null 2>&1 || true

# Replace rather than merge, so files removed upstream do not linger.
rm -rf "$APP"
cp -R build/bundle/Barrier.app "$APP"

codesign --verify --deep --strict "$APP" 2>/dev/null \
    && echo "Signature verified" \
    || warn "Signature did not verify; Accessibility may refuse the app."

# --- 4. restart --------------------------------------------------------------
if [ "$WAS_RUNNING" -eq 1 ]; then
    say "Restarting Barrier"
    open "$APP"
else
    say "Done"
    echo "Barrier was not running, so it was not restarted. Start it with:"
    echo "    open $APP"
fi

cat <<'EOF'

------------------------------------------------------------
If the server now fails with "assistive devices does not
trust this process":

  System Settings -> Privacy & Security -> Accessibility
  Remove Barrier with "-", then add it again, or toggle it
  off and on.

The app is ad-hoc signed, which is the best a locally built
app can do without an Apple Developer certificate, and its
identity changes on every rebuild. macOS sometimes drops the
permission when that happens. Nothing is wrong.

Your certificate and trusted fingerprints were not touched.
------------------------------------------------------------
EOF
