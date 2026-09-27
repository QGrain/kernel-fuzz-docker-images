#!/usr/bin/env bash
set -Eeuo pipefail
source /usr/local/lib/kernel-fuzz/common.sh
require_amd64

: "${GO_VERSION:?}" "${GO_SHA256:?}" "${PYTHON_VERSION:?}"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

download_with_retries() {
    local attempt
    for attempt in 1 2 3 4 5; do
        if download_checked "$@"; then
            return 0
        fi
        if [[ $attempt != 5 ]]; then
            echo "Download failed (attempt $attempt/5); retrying..." >&2
            sleep 2
        fi
    done
    return 1
}

download_with_retries \
    "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
    "$GO_SHA256" "$tmp_dir/go.tar.gz"
go_root="/root/software/go${GO_VERSION}"
mkdir -p "$go_root" /root/software/gopath
tar -xzf "$tmp_dir/go.tar.gz" -C "$go_root" --strip-components=1
"$go_root/bin/go" version

download_with_retries \
    'https://github.com/Kitware/CMake/releases/download/v3.31.10/cmake-3.31.10-linux-x86_64.tar.gz' \
    '3cb3dd247b6a1de2d0f4b20c6fd4326c9024e894cebc9dc8699758887e566ca7' \
    "$tmp_dir/cmake.tar.gz"
mkdir -p /opt/cmake
tar -xzf "$tmp_dir/cmake.tar.gz" -C /opt/cmake --strip-components=1
ln -sf /opt/cmake/bin/cmake /usr/local/bin/cmake
ln -sf /opt/cmake/bin/ctest /usr/local/bin/ctest
ln -sf /opt/cmake/bin/cpack /usr/local/bin/cpack
/usr/local/bin/cmake --version

download_with_retries \
    'https://github.com/conda-forge/miniforge/releases/download/26.7.2-0/Miniforge3-26.7.2-0-Linux-x86_64.sh' \
    '281b0ac7d550802efc81af633225a5e6116d29ae72f3ab4eae7168c3931a4c05' \
    "$tmp_dir/miniforge.sh"
bash "$tmp_dir/miniforge.sh" -b -p /opt/miniforge
/opt/miniforge/bin/conda config --system --set auto_activate_base false
/opt/miniforge/bin/conda create --yes --name kernel-fuzz \
    "python=${PYTHON_VERSION}" pip
/opt/miniforge/envs/kernel-fuzz/bin/python -m pip install --no-cache-dir \
    'syzqemuctl==0.4.0'
/opt/miniforge/bin/conda clean --all --yes
/opt/miniforge/envs/kernel-fuzz/bin/syzqemuctl --version

download_with_retries \
    'https://github.com/pwndbg/pwndbg/releases/download/2026.07.29/pwndbg_2026.07.29_x86_64-portable.tar.xz' \
    '63c38b76bf8baeb44b4bc018c73ea0b05b872c2aba205ed5680892f2d65adb03' \
    "$tmp_dir/pwndbg.tar.xz"
mkdir -p /opt/pwndbg
tar -xJf "$tmp_dir/pwndbg.tar.xz" -C /opt/pwndbg
ln -sf /opt/pwndbg/pwndbg/bin/gdb /usr/local/bin/gdb
ln -sf /opt/pwndbg/pwndbg/bin/pwndbg /usr/local/bin/pwndbg
/usr/local/bin/gdb --version >/dev/null
/usr/local/bin/pwndbg --version >/dev/null

download_with_retries \
    'https://github.com/QGrain/cvm/releases/download/v0.1.2/cvm-x86_64-unknown-linux-musl.tar.gz' \
    '978fbb6977898019faa60528b75eb195176f5ff94fc6ee667e70c8f8836e3030' \
    "$tmp_dir/cvm.tar.gz"
mkdir -p /root/.cvm/bin
tar -xzf "$tmp_dir/cvm.tar.gz" -C /root/.cvm/bin cvm
chmod 0755 /root/.cvm/bin/cvm
CVM_HOME=/root/.cvm /root/.cvm/bin/cvm init > /root/.cvm/cvm.sh
/root/.cvm/bin/cvm version
