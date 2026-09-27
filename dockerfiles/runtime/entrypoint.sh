#!/usr/bin/env bash
set -Eeuo pipefail

[ -f /root/.bash_env ] && . /root/.bash_env
if [[ ${KERNEL_FUZZ_START_SSHD:-1} == 1 ]]; then
    mkdir -p /run/sshd
    ssh-keygen -A >/dev/null
    /usr/sbin/sshd
fi

if [[ ${KERNEL_FUZZ_INIT_TEMPLATE:-1} == 1 ]]; then
    if ! /usr/local/bin/kernel-fuzz-init-template; then
        echo 'Warning: syzqemuctl template initialization failed; the container remains usable.' >&2
    fi
fi

exec "$@"
