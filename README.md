# Kernel fuzzing Docker images

[中文](README_CN.md) | English

[![Docker Hub pulls](https://img.shields.io/docker/pulls/qgrain/kernel-fuzz?logo=docker&label=Docker%20Hub%20pulls)](https://hub.docker.com/r/qgrain/kernel-fuzz)
[![Docker image size](https://img.shields.io/docker/image-size/qgrain/kernel-fuzz/latest?logo=docker&label=latest%20image%20size)](https://hub.docker.com/r/qgrain/kernel-fuzz/tags)
[![License](https://img.shields.io/github/license/QGrain/kernel-fuzz-docker-images)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-linux%2Famd64-0db7ed?logo=docker)](https://hub.docker.com/r/qgrain/kernel-fuzz)

Versioned Dockerfiles for `qgrain/kernel-fuzz`, targeting x86_64 Linux kernel
fuzzing with QEMU/KVM. They use [cvm 0.1.2](https://github.com/QGrain/cvm/releases/tag/v0.1.2)
for compilers and [syzqemuctl 0.4.0](https://github.com/QGrain/syzqemuctl/tree/v0.4.0)
for guest images. The Ubuntu tag is the container userspace, not the kernel
under test; the latter runs in a guest VM. ARM64/Android guests are deferred.

| Docker Hub tag | Ubuntu | cvm GCC | cvm LLVM (`X86`) | Go | active Conda Python | pinned syzkaller source |
| --- | --- | --- | --- | --- | --- | --- |
| `2004_v2` | 20.04 | 12.3.0 | 17.0.6 | 1.24.8 | 3.10 | `6e83b42` (2025-06-30) |
| `2204_v3` | 22.04 | 13.4.0 | 19.1.7 | 1.24.8 | 3.10 | `6e83b42` (2025-06-30) |
| `2404_v1` | 24.04 | 14.2.0 | 21.1.8 | 1.26.5 | 3.12 | `544adce` (2026-07-23) |
| `2604_v1` | 26.04 | 15.3.0 | 22.1.8 | 1.26.5 | 3.14 | `544adce` (2026-07-23) |

`latest` is intended to track the broadly compatible `2404_v1` release after
all local checks pass. `2004_v2` is kept as a legacy compatibility image for
older kernel experiments; prefer `2404_v1` for new work unless a specific old
userspace is required.

## Layout and image layers

```text
dockerfiles/
  Dockerfile_<tag>              four release definitions
  build/                        files copied only into build stages
    config/llvm-22.toml          LLVM 22/cvm compatibility override
  runtime/                      small commands retained by the final image
  config/                       shell, editor, and sshd configuration
scripts/                        host-side build, template, and test helpers
docs/                           longer operational documentation
```

Each release Dockerfile starts from a digest-qualified upstream Ubuntu base and
has these stages: `base` (OS packages), `tooling` (Go, CMake, Miniforge, cvm),
and `compilers` (GCC and LLVM). The `compilers` target is tagged locally as
`kernel-fuzz-build:<tag>-base`; `final` then uses that exact local image and
adds the fixed syzkaller source, runtime configuration, and guest template.
The Ubuntu manifest digest is pinned so a release rebuild starts from the same
root filesystem. Apt packages and Debian guest packages are still resolved at
build time, so this is not bit-for-bit package-level reproducibility.

`kernel-fuzz-build:*` is a build cache boundary, not a public product and must
not be pushed to Docker Hub. It has no compatibility contract, and Docker
already deduplicates its layers when a final image is pushed. A registry cache
or a private CI cache is the appropriate place for remote build acceleration,
if one is ever needed. The `base`, `tooling`, and `compilers` targets can also
be built under `kernel-fuzz-test:*` for diagnosis.

The 26.04 image has one explicit cvm profile,
`dockerfiles/build/config/llvm-22.toml`. In cvm 0.1.2, the default LLVM 22
project/runtime selection creates the CMake target `check-builtins` twice.
The profile requests the X86 backend, `clang` and `lld` projects, and
`compiler-rt` only as a runtime. It is a narrow, tested workaround rather than
a general per-release configuration; it is copied only into the compiler build
stage and is absent from the final image.

## Included environment

The same Miniforge 26.7.2 installer is used in every image. Its `base` Python
is 3.14; the automatically activated `kernel-fuzz` environment supplies the
Python version in the table. Miniforge provides ordinary `conda create` and
`conda activate` commands and uses conda-forge by default.

Go is installed at `/root/software/goX.Y.Z`, with
`GOPATH=/root/software/gopath`. The fixed syzkaller checkout is at
`/root/fuzzers/syzkaller-7bitHASH-YYYYMMDD`. It is deliberately **source only**:
the image build does not run `make`, so there is no prebuilt `bin/` directory.
Build it in the working container for the target you need.

`/root/.bash_env` is loaded by both `/root/.profile` and `/root/.bashrc`
before Bash's non-interactive early return. Consequently an interactive shell
and `docker exec NAME bash -lc '…'` receive the same Go, cvm, and Conda
environment. Build-only helpers are removed from `/usr/local/lib/kernel-fuzz`;
the retained runtime commands are under `/usr/local/bin`.

## Build locally

Docker BuildKit and tens of GiB of free disk per compiler build are required.
The Dockerfiles never declare a proxy `ARG` or `ENV`. If the build host needs a
proxy, export Docker's predefined proxy variables only for that invocation:

```bash
export http_proxy='http://YOUR_PROXY_HOST:PORT'
export https_proxy="$http_proxy"
export HTTP_PROXY="$http_proxy"
export HTTPS_PROXY="$http_proxy"
CVM_JOBS=32 bash scripts/build-image.sh 2404_v1
bash scripts/test-image.sh qgrain/kernel-fuzz:2404_v1
```

`CVM_JOBS` defaults to 16 and may be raised to 32 or 48 when CPU and memory
allow. There is no `SYZKALLER_JOBS` build argument: syzkaller is no longer
compiled while constructing the image.

The expensive compiler boundary makes normal iteration incremental:

```bash
# First build, or after changing packages/toolchains/Miniforge/Go/CMake.
CVM_JOBS=32 bash scripts/build-image.sh 2404_v1 release-base

# After changing fixed syzkaller source selection or final runtime configuration.
bash scripts/build-image.sh 2404_v1 final

# Both phases (the default when no second argument is supplied).
CVM_JOBS=32 bash scripts/build-image.sh 2404_v1 all
```

`final` requires the corresponding local `kernel-fuzz-build:<tag>-base`; it
does not silently rebuild it. This makes a base rebuild an explicit decision.
For a final image, the helper embeds `/root/images/image-template` as the last
layer. The 20.04/22.04 releases use Bullseye and the 24.04/26.04 releases use
Trixie. Local template caches are tagged
`kernel-fuzz-template-cache:{bullseye,trixie}`. Set
`KERNEL_FUZZ_EMBED_TEMPLATE=0` only for development builds intentionally
without a guest template.

No publish happens in this workflow. After checking all images, create local
`latest` from 24.04. Release builds should be made from a clean Git commit so
the final images get useful OCI provenance labels:

```bash
git status --short
CVM_JOBS=32 bash scripts/build-image.sh 2404_v1 release-base
bash scripts/build-image.sh 2404_v1 final
bash scripts/test-image.sh qgrain/kernel-fuzz:2404_v1
docker image inspect qgrain/kernel-fuzz:2404_v1 \
  --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}'
docker tag qgrain/kernel-fuzz:2404_v1 qgrain/kernel-fuzz:latest
```

Publish only if explicitly desired and after authenticating outside this
repository:

```bash
docker login -u qgrain
for tag in 2004_v2 2204_v3 2404_v1 2604_v1 latest; do
  docker push "qgrain/kernel-fuzz:$tag"
done
```

## Run

For a durable development container, use a command that keeps PID 1 alive:

```bash
docker run -d --name kernel-fuzz \
  --privileged \
  -p 127.0.0.1:2222:22 \
  -v /HOST/PATH/KERNELS:/root/kernels \
  qgrain/kernel-fuzz:2404_v1 sleep infinity

docker exec -it kernel-fuzz bash
```

`--privileged` is required by syzqemuctl's guest-image initialization and
normally makes the host `/dev/kvm` available for QEMU acceleration. Verify the
host has KVM before depending on it. The entrypoint starts sshd and verifies
the embedded `image-template`. If an empty mount or volume hides
`/root/images`, it attempts to recreate the template; that fallback needs
outbound Debian access and any required **runtime** proxy variables. Reuse the
initialized volume afterwards.

The root password is locked by default. Enable password SSH only after the
container starts with `docker exec -it kernel-fuzz passwd`; alternatively add
your own `/root/.ssh/authorized_keys`. Bind SSH to localhost unless you have a
separate, reviewed network policy. Set `KERNEL_FUZZ_START_SSHD=0` to skip
starting sshd for local-only containers. Never put a proxy into `.bash_env`;
pass one at runtime with `docker run -e http_proxy -e https_proxy -e no_proxy`
only when needed.

The embedded syzqemuctl guest template includes SSH key material for disposable
fuzzing VMs, including `disk.id_rsa`. Treat it as public infrastructure for
isolated experiments, not as a secret that can protect a networked or valuable
guest.

Additional operational notes:

- [Build cache and incremental rebuild notes, Chinese](docs/build-cache_CN.md)
- [Manual verification checklist, Chinese](docs/manual-verification_CN.md)
- [Pre-release checklist, Chinese](docs/release-checklist_CN.md)

The verification checklist covers toolchains, template cloning, KVM, package
headers, SSH, and coding-agent shells.

## Compatibility and scope

The intended matrix is x86_64 mainstream LTS 5.x/6.x, Linux 7.x, and current
mainline. The images provide build prerequisites, not a promise that one
compiler version builds every historical kernel without patches. Use
`cvm use system` or install/select another cvm compiler when a tree rejects a
newer GCC or LLVM. Rust-for-Linux, all optional filesystems, and non-x86 guest
architectures are outside this first iteration.

The pinned 2026 syzkaller revision declares Go 1.26.0, while the 2025 revision
declares Go 1.23.7. The 20.04/22.04 releases intentionally use Go 1.24.8 for
their 2025 source; building the newer syzkaller there may need a newer Go
toolchain and network access. Older Ubuntu archives can also provide a
`pahole` below a current-mainline BTF requirement; upgrade it for that exact
configuration or disable `CONFIG_DEBUG_INFO_BTF`.
