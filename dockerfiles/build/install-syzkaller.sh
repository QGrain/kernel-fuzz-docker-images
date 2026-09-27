#!/usr/bin/env bash
set -Eeuo pipefail
: "${SYZKALLER_COMMIT:?}" "${SYZKALLER_DATE:?}"

short_commit=${SYZKALLER_COMMIT:0:7}
dest="/root/fuzzers/syzkaller-${short_commit}-${SYZKALLER_DATE}"
git init -q "$dest"
git -C "$dest" remote add origin https://github.com/google/syzkaller.git
git -C "$dest" fetch --depth 1 origin "$SYZKALLER_COMMIT"
git -C "$dest" -c advice.detachedHead=false checkout --detach -q FETCH_HEAD
test "$(git -C "$dest" rev-parse HEAD)" = "$SYZKALLER_COMMIT"
test -f "$dest/Makefile"

# Keep the pinned source, but never build syzkaller into the image.  Users
# select their target and invoke make themselves; that avoids storing a large
# host-only bin/ directory in every published image.
