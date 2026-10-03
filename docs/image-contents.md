# kernel-fuzz image contents and configuration inventory

This document records what the published `qgrain/kernel-fuzz` images install
and configure. It is intended for users who need to know what is available
inside the container, and for maintainers who need a stable checklist before
changing a release image.

The package names below are the requested Ubuntu/Debian package names. Exact
apt package versions are resolved at build time by the pinned Ubuntu base image
and the configured apt mirrors; they are not pinned one by one.

## Release matrix

| Tag | Ubuntu base | GCC | LLVM/Clang | Go | Conda env Python | syzkaller source | Guest template |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `2004_v2` | `ubuntu:20.04@sha256:c664f8...` | 12.3.0 | 17.0.6 | 1.24.8 | 3.10 | `6e83b42` (2025-06-30) | Debian Bullseye |
| `2204_v3` | `ubuntu:22.04@sha256:281c57...` | 13.4.0 | 19.1.7 | 1.24.8 | 3.10 | `6e83b42` (2025-06-30) | Debian Bullseye |
| `2404_v1` | `ubuntu:24.04@sha256:496754...` | 14.2.0 | 21.1.8 | 1.26.5 | 3.12 | `544adce` (2026-07-23) | Debian Trixie |
| `2604_v1` | `ubuntu:26.04@sha256:61ebaa...` | 15.3.0 | 22.1.8 | 1.26.5 | 3.14 | `544adce` (2026-07-23) | Debian Trixie |

`latest` should point to `2404_v1`.

## System package groups

All release images request the following common Ubuntu packages:

```text
apt-transport-https autoconf bash-completion bc binfmt-support binutils bison
build-essential bzip2 ca-certificates cmake cpio curl debootstrap
debian-archive-keyring dwarves e2fsprogs elfutils file flex gawk gdb gdbserver
git gnupg htop iproute2 kmod less libbluetooth-dev libcap-dev libc6-dbg
libc6-dev libc6-dev-i386 libdw-dev libedit-dev libelf-dev libgmp-dev
liblz4-dev liblzma-dev libmpc-dev libmpfr-dev libncurses-dev libssl-dev
libunwind-dev libzstd-dev linux-libc-dev lz4 lzop make nano net-tools
ninja-build openssh-client openssh-server pkg-config procps protobuf-compiler
python3 python3-dev python3-pip python3-venv qemu-system-x86 qemu-utils rsync
screen ssh strace sudo swig tmux u-boot-tools unzip util-linux vim wget
xz-utils zip zlib1g-dev zstd
```

The build also attempts to install these optional filesystem/network utilities
when the Ubuntu release provides them:

```text
btrfs-progs dosfstools erofs-utils exfatprogs f2fs-tools gfs2-utils jfsutils
netcat-openbsd ocfs2-tools reiserfsprogs squashfs-tools xfsprogs
```

These packages are chosen to cover common syzkaller and Linux kernel build
needs: compiler prerequisites, kernel headers and userspace libraries, QEMU/KVM,
Debian guest-image generation, debugging, compression formats, filesystem
utilities, networking diagnostics, SSH, and interactive development.

## Source and binary tools installed outside apt

The following tools are installed from upstream release archives or source
repositories:

| Tool | Location | Version/source | Notes |
| --- | --- | --- | --- |
| Go | `/root/software/goX.Y.Z` | Per release matrix | `GOROOT` points here. |
| GOPATH | `/root/software/gopath` | Directory only | `GOPATH` points here. |
| CMake | `/opt/cmake` | 3.31.10 | Symlinked into `/usr/local/bin`. |
| Miniforge | `/opt/miniforge` | 26.7.2 | `base` auto-activation disabled. |
| Conda env | `/opt/miniforge/envs/kernel-fuzz` | Python per release matrix | Auto-activated by shell config. |
| syzqemuctl | Conda `kernel-fuzz` env | 0.4.0 | Installed with pip. |
| cvm | `/root/.cvm/bin/cvm` | 0.1.2 | Initializes `/root/.cvm/cvm.sh`. |
| GCC | `/root/.cvm/toolchains/gcc/<version>` | Per release matrix | Installed and selected by cvm. |
| LLVM/Clang | `/root/.cvm/toolchains/llvm/<version>` | Per release matrix | Installed and selected by cvm. |
| pwndbg portable | `/opt/pwndbg` | 2026.07.29 | `gdb` and `pwndbg` symlinked to `/usr/local/bin`. |
| syzkaller source | `/root/fuzzers/syzkaller-7bitHASH-YYYYMMDD` | Per release matrix | Source checkout only; not built. |
| fzf | `/root/.fzf` | `v0.74.4` | Installed with upstream git installer and `--no-update-rc`. |

For `2604_v1`, LLVM 22 is installed with
`dockerfiles/build/config/llvm-22.toml`. The profile keeps the X86 target,
`clang` and `lld`, and treats `compiler-rt` as a runtime to avoid a duplicate
`check-builtins` target issue in cvm 0.1.2's default LLVM 22 project/runtime
selection.

## Directory layout

The images create and reserve these working directories:

```text
/root/fuzzers              syzkaller and other fuzzer source trees
/root/images               syzqemuctl-managed QEMU images
/root/images/image-template embedded default guest template
/root/kernels              intended kernel source/build workspace
/root/software             downloaded source/binary tool payloads
/root/software/goX.Y.Z     Go toolchain
/root/software/gopath      GOPATH
/root/.cvm                 cvm state, defaults, and installed toolchains
/opt/cmake                 upstream CMake installation
/opt/miniforge             Miniforge installation and kernel-fuzz Conda env
/opt/pwndbg                portable pwndbg bundle
```

Build-only helper scripts are removed from `/usr/local/lib/kernel-fuzz` in the
final image. Runtime commands retained in `/usr/local/bin` include:

```text
kernel-fuzz-entrypoint
kernel-fuzz-init-template
kernel-fuzz-smoke-test
```

## Shell environment

Common development environment setup is centralized in `/root/.bash_env`.
Both `/root/.profile` and `/root/.bashrc` load it at the beginning; in
`.bashrc`, this happens before the usual non-interactive early return. This is
intentional so that both human shells and automation such as:

```bash
docker exec NAME bash -lc 'go version && clang --version'
```

receive the same Go, cvm, Conda, compiler, and fzf environment.

The file exports or initializes:

```text
GOROOT=/root/software/goX.Y.Z
GOPATH=/root/software/gopath
CVM_HOME=/root/.cvm
PATH entries for Go, GOPATH/bin, CMake, cvm, selected GCC/LLVM, Conda, and fzf
Conda environment: kernel-fuzz
Interactive fzf Bash integration
```

No proxy variables are stored in `/root/.bash_env` or in image metadata.

## Runtime entrypoint behavior

The default entrypoint performs two runtime checks before executing the user
command:

1. If `KERNEL_FUZZ_START_SSHD=1` or unset, it generates host keys as needed and
   starts `sshd`.
2. If `KERNEL_FUZZ_INIT_TEMPLATE=1` or unset, it verifies
   `/root/images/image-template`. If a mount hides the embedded template, it
   attempts to initialize a new template with syzqemuctl. That fallback needs a
   privileged container and network access to Debian mirrors.

Set `KERNEL_FUZZ_START_SSHD=0` for local-only `docker exec` containers. Set
`KERNEL_FUZZ_INIT_TEMPLATE=0` only when deliberately managing `/root/images`
yourself.

## SSH configuration

The image installs `/etc/ssh/sshd_config.d/50-kernel-fuzz.conf` with:

```text
PermitRootLogin yes
PasswordAuthentication yes
PermitEmptyPasswords no
```

The root account password remains locked by default. Users must run `passwd`
inside their own container or add `authorized_keys` before SSH login.

## Guest image template

Final images embed `/root/images/image-template` as the last image layer:

- `2004_v2` and `2204_v3` embed a Debian Bullseye template.
- `2404_v1`, `2604_v1`, and `latest` embed a Debian Trixie template.

The template is managed by syzqemuctl and can be cloned, listed, started, and
deleted with syzqemuctl commands. Guest SSH key material in the template is
disposable fuzzing infrastructure and should be treated as public.

## User-facing configuration files

The images install lightweight root-level configuration for interactive work:

```text
/root/.bash_env
/root/.profile
/root/.bashrc
/root/.vimrc
/root/.screenrc
/root/.tmux.conf
/etc/motd
/etc/ssh/sshd_config.d/50-kernel-fuzz.conf
```

The `/etc/motd` login message summarizes root SSH status, syzqemuctl image
management, cvm/environment loading, and proxy policy. The source file does
not contain trailing blank lines, but the final installed `/etc/motd` appends
two extra newlines to keep some visual space before the login shell prompt.

## What is intentionally not included

- No built syzkaller `bin/` directory.
- No prebuilt Linux kernel.
- No hard-coded proxy, credentials, SSH authorized keys, or root password.
- No public `kernel-fuzz-build:*` release images; those are local build-cache
  boundaries only.
- No ARM64, Android, or RISC-V guest workflow in the current release series.
