#!/usr/bin/env bash
# Run the installer round-trip test under bash 3.2 -- the bash people on
# stock macOS are piping this installer into.
#
# The container needs two things the base image lacks: curl (busybox wget
# cannot fetch the file:// URLs the test serves from) and a non-root user
# (the installer refuses to run as root, which is the point, so running the
# whole suite as root would make every install case trivially "pass" by
# refusing).
set -euo pipefail

IMAGE="docker.io/library/bash:3.2"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if command -v podman >/dev/null 2>&1; then
    ENGINE="podman"
    MOUNT_OPTS=":ro,Z"
elif command -v docker >/dev/null 2>&1; then
    ENGINE="docker"
    MOUNT_OPTS=":ro"
else
    echo "Neither podman nor docker found. Install one of them first." >&2
    exit 1
fi

exec "${ENGINE}" run --rm \
    -v "${REPO_ROOT}:/src${MOUNT_OPTS}" \
    -w /tmp \
    "${IMAGE}" \
    sh -c '
        apk add --no-cache curl diffutils >/dev/null &&
        adduser -D tester &&
        bash --version | head -1 &&
        su tester -c "bash /src/tests/install-test.sh"
    '
