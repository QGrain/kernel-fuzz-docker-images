#!/usr/bin/env bash
set -Eeuo pipefail
source /usr/local/lib/kernel-fuzz/common.sh
require_amd64

export DEBIAN_FRONTEND=noninteractive
apt_options=(-o Acquire::Retries=5)
apt-get "${apt_options[@]}" update
apt-get "${apt_options[@]}" install -y --no-install-recommends \
    apt-transport-https autoconf bash-completion bc binfmt-support binutils bison build-essential \
    bzip2 ca-certificates cmake cpio curl debootstrap debian-archive-keyring \
    dwarves e2fsprogs elfutils file flex \
    gawk gdb gdbserver git gnupg \
    htop iproute2 kmod less libbluetooth-dev libcap-dev libc6-dbg libc6-dev \
    libc6-dev-i386 libdw-dev libedit-dev libelf-dev libgmp-dev \
    liblz4-dev liblzma-dev libmpc-dev libmpfr-dev libncurses-dev libssl-dev \
    libunwind-dev libzstd-dev linux-libc-dev lz4 lzop make nano net-tools ninja-build \
    openssh-client openssh-server pkg-config procps protobuf-compiler \
    python3 python3-dev python3-pip python3-venv qemu-system-x86 \
    qemu-utils rsync screen ssh \
    strace sudo swig tmux u-boot-tools unzip util-linux vim wget xz-utils \
    zip zlib1g-dev zstd

install_optional_package() {
    local package=$1
    local attempt
    for attempt in 1 2 3 4 5; do
        if apt-get "${apt_options[@]}" install -y --no-install-recommends "$package"; then
            return 0
        fi
        echo "Retrying optional package $package after transient apt failure ($attempt/5)" >&2
        apt-get "${apt_options[@]}" update || true
        sleep 2
    done
    echo "Failed to install optional package $package after retries" >&2
    return 1
}

# Filesystem tools from syzkaller's syz-env, where the Ubuntu series supplies them.
for package in btrfs-progs dosfstools erofs-utils exfatprogs f2fs-tools \
    gfs2-utils jfsutils netcat-openbsd ocfs2-tools reiserfsprogs \
    squashfs-tools xfsprogs; do
    candidate=$(apt-cache policy "$package" | awk '$1 == "Candidate:" {print $2}')
    if [[ -n $candidate && $candidate != '(none)' ]]; then
        install_optional_package "$package"
    fi
done

mkdir -p /root/fuzzers /root/kernels /root/images /root/software/gopath
apt-get clean
rm -rf /var/lib/apt/lists/*
