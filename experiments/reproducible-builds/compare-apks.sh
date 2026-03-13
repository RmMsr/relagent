#!/usr/bin/env sh
# Compare two APKs for reproducibility.
#
# Usage: compare-apks.sh <apk1> <apk2>

set -eu

if [ $# -ne 2 ]; then
    echo "Usage: $0 <apk1> <apk2>" >&2
    exit 1
fi

APK1="$1"
APK2="$2"

for f in "$APK1" "$APK2"; do
    if [ ! -f "$f" ]; then
        echo "Error: $f not found" >&2
        exit 1
    fi
done

log() { echo "==> $*"; }

TMPDIR="${TMPDIR:-/tmp}"
WORK="$TMPDIR/compare-apks-$$"
mkdir -p "$WORK/a" "$WORK/b"

# shellcheck disable=SC2329
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

log "Comparing APKs"
echo "    A: $APK1  ($(stat -c '%y' "$APK1" 2>/dev/null || stat -f '%Sm' "$APK1"))"
echo "    B: $APK2  ($(stat -c '%y' "$APK2" 2>/dev/null || stat -f '%Sm' "$APK2"))"

if cmp -s "$APK1" "$APK2"; then
    log "IDENTICAL — builds are reproducible"
    exit 0
fi

log "APKs differ — investigating"

# Unpack both
unzip -q -o "$APK1" -d "$WORK/a"
unzip -q -o "$APK2" -d "$WORK/b"

# Find files only in one side
ONLY_A="$(cd "$WORK" && find a -type f | sed 's|^a/||' | sort)"
ONLY_B="$(cd "$WORK" && find b -type f | sed 's|^b/||' | sort)"

MISSING_FROM_B="$(echo "$ONLY_A" | grep -vxF "$ONLY_B" || true)"
MISSING_FROM_A="$(echo "$ONLY_B" | grep -vxF "$ONLY_A" || true)"

if [ -n "$MISSING_FROM_B" ]; then
    log "Files only in A:"
    echo "$MISSING_FROM_B" | sed 's/^/    /'
fi
if [ -n "$MISSING_FROM_A" ]; then
    log "Files only in B:"
    echo "$MISSING_FROM_A" | sed 's/^/    /'
fi

# Compare common files
COMMON="$(echo "$ONLY_A" | grep -xF "$ONLY_B" || true)"
DIFFERING=""
for f in $COMMON; do
    if ! cmp -s "$WORK/a/$f" "$WORK/b/$f"; then
        DIFFERING="$DIFFERING $f"
    fi
done

if [ -z "$DIFFERING" ]; then
    log "All common files are identical — difference is in ZIP metadata only"
    echo "    Hint: try 'repro-apk diff-zip-meta $APK1 $APK2'"
    exit 1
fi

log "Files that differ:"
for f in $DIFFERING; do
    SIZE_A="$(wc -c < "$WORK/a/$f")"
    SIZE_B="$(wc -c < "$WORK/b/$f")"
    if [ "$SIZE_A" = "$SIZE_B" ]; then
        echo "    $f  (same size: $SIZE_A bytes)"
    else
        echo "    $f  (A: $SIZE_A bytes, B: $SIZE_B bytes)"
    fi
done

# Check libapp.so paths if it's among the differing files
for f in $DIFFERING; do
    case "$f" in
        */libapp.so)
            log "Embedded paths in libapp.so:"
            PATHS_A="$(strings "$WORK/a/$f" | grep '^file:///' || true)"
            PATHS_B="$(strings "$WORK/b/$f" | grep '^file:///' || true)"
            echo "    A:"
            if [ -n "$PATHS_A" ]; then
                echo "$PATHS_A" | sed 's/^/        /'
            else
                echo "        (none)"
            fi
            echo "    B:"
            if [ -n "$PATHS_B" ]; then
                echo "$PATHS_B" | sed 's/^/        /'
            else
                echo "        (none)"
            fi
            if [ "$PATHS_A" != "$PATHS_B" ]; then
                echo "    Hint: build both from the same path (e.g. /tmp/build/org.venkado.relagent)"
            fi
            ;;
    esac
done

# Suggest diffoscope for remaining differences
log "For detailed analysis run:"
echo "    diffoscope $APK1 $APK2"

exit 1
