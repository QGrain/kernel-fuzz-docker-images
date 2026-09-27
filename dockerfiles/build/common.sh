#!/usr/bin/env bash
set -Eeuo pipefail

download_checked() {
    local url=$1 expected=$2 output=$3
    curl --fail --location --retry 5 --retry-delay 2 --silent --show-error "$url" -o "$output"
    printf '%s  %s\n' "$expected" "$output" | sha256sum --check --status
}

require_amd64() {
    if [[ $(uname -m) != x86_64 ]]; then
        echo 'These images currently support linux/amd64 only.' >&2
        exit 1
    fi
}
