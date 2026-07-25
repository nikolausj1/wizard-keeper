#!/bin/bash
# Release guard for the clean (all-ages) targets: WizardKeeper and
# OhHellKeeper must never ship the 18+ Spicy announcer tier. Fails loudly
# if a built .app either contains an AnnouncerSpicy directory, or contains
# any tail_3_* / leadin_3_* clip file (the spicy-bucket naming) anywhere
# else in the bundle — belt-and-suspenders in case a spicy clip ever ends
# up outside AnnouncerSpicy/, e.g. still in the shared Announcer/ folder
# from a corpus that hasn't been cleaned up yet.
#
# Usage: tools/check_clean_bundle.sh /path/to/WizardKeeper.app
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 /path/to/Built.app" >&2
    exit 2
fi

APP_PATH="$1"

if [ ! -d "$APP_PATH" ]; then
    echo "check_clean_bundle: no such app bundle: $APP_PATH" >&2
    exit 2
fi

FAILED=0

if [ -d "$APP_PATH/AnnouncerSpicy" ]; then
    echo "FAIL: $APP_PATH bundles an AnnouncerSpicy directory — clean targets must not ship the spicy clip pack." >&2
    FAILED=1
fi

SPICY_FILES=$(find "$APP_PATH" \( -name "tail_3_*" -o -name "leadin_3_*" \) 2>/dev/null || true)
if [ -n "$SPICY_FILES" ]; then
    echo "FAIL: $APP_PATH contains spicy-bucket clip file(s):" >&2
    echo "$SPICY_FILES" >&2
    FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
    echo "check_clean_bundle: $APP_PATH is NOT clean." >&2
    exit 1
fi

echo "check_clean_bundle: $APP_PATH is clean — no AnnouncerSpicy directory, no tail_3_*/leadin_3_* clips."
exit 0
