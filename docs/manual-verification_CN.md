# kernel-fuzz 镜像人工验证清单

这份清单用于在本机创建容器后，手动验收四个 release 镜像，尤其是 `2204_v3`、`2404_v1`
和 `2604_v1`。它假设镜像已经在本地构建完成，且目标主要是 x86_64 QEMU/KVM kernel fuzzing。

建议先验证 `2404_v1`，再验证 `2204_v3` 和 `2604_v1`，最后抽查 `2004_v2`。这样可以先覆盖
`latest` 候选，再覆盖一个较旧 LTS 和一个最新 LTS。

## 0. 宿主机前置检查

```bash
uname -m
docker version
docker buildx version
test -e /dev/kvm && ls -l /dev/kvm
docker image ls qgrain/kernel-fuzz
docker image ls kernel-fuzz-build
docker image ls kernel-fuzz-template-cache
```

期望：

| 项目 | 期望结果 |
| --- | --- |
| `uname -m` | `x86_64` 或 `amd64` 宿主机 |
| `/dev/kvm` | 存在且当前用户可通过 Docker privileged 容器访问 |
| `qgrain/kernel-fuzz:*` | 存在 `2004_v2`、`2204_v3`、`2404_v1`、`2604_v1` |
| `kernel-fuzz-build:*` | 只作为本地构建缓存存在，不准备发布 |
| `kernel-fuzz-template-cache:*` | 可选缓存，用于加速 final 镜像模板嵌入 |

## 1. 镜像静态检查

逐个检查最终镜像没有持久化 proxy：

```bash
for image in \
  qgrain/kernel-fuzz:2004_v2 \
  qgrain/kernel-fuzz:2204_v3 \
  qgrain/kernel-fuzz:2404_v1 \
  qgrain/kernel-fuzz:2604_v1
do
  echo "== $image =="
  docker image inspect "$image" | python3 -c '
import json, sys
image = json.load(sys.stdin)[0]
env = image.get("Config", {}).get("Env") or []
bad = [item for item in env if item.split("=", 1)[0].lower() in {
    "http_proxy", "https_proxy", "all_proxy", "no_proxy"}]
if bad:
    raise SystemExit("proxy env persisted: " + repr(bad))
'
  docker history --no-trunc "$image" | python3 -c '
import sys
history = sys.stdin.read().lower()
if any(name in history for name in ("http_proxy", "https_proxy", "all_proxy")):
    raise SystemExit("proxy setting appears in image history")
'
done
```

期望：无输出错误。构建代理只能在构建时临时传递，不能进入 image config 或 history。

再检查 OCI provenance labels：

```bash
for image in \
  qgrain/kernel-fuzz:2004_v2 \
  qgrain/kernel-fuzz:2204_v3 \
  qgrain/kernel-fuzz:2404_v1 \
  qgrain/kernel-fuzz:2604_v1
do
  echo "== $image =="
  docker image inspect "$image" \
    --format 'source={{ index .Config.Labels "org.opencontainers.image.source" }} revision={{ index .Config.Labels "org.opencontainers.image.revision" }} base={{ index .Config.Labels "org.opencontainers.image.base.name" }}'
done
```

期望：`source` 指向本仓库，`revision` 是待发布 commit，`base` 是带 `@sha256:` 的 Ubuntu
基础镜像。

## 2. 创建待测容器

不要先挂载空的 `/root/images`，否则会遮住镜像内置的 template。首次人工验证建议直接使用镜像内置
`/root/images/image-template`：

```bash
docker rm -f kf2004 kf2204 kf2404 kf2604 2>/dev/null || true

docker run -d --name kf2004 --hostname kf2004 --privileged \
  -p 127.0.0.1:2204:22 qgrain/kernel-fuzz:2004_v2 sleep infinity
docker run -d --name kf2204 --hostname kf2204 --privileged \
  -p 127.0.0.1:2224:22 qgrain/kernel-fuzz:2204_v3 sleep infinity
docker run -d --name kf2404 --hostname kf2404 --privileged \
  -p 127.0.0.1:2244:22 qgrain/kernel-fuzz:2404_v1 sleep infinity
docker run -d --name kf2604 --hostname kf2604 --privileged \
  -p 127.0.0.1:2264:22 qgrain/kernel-fuzz:2604_v1 sleep infinity
```

检查 entrypoint 日志：

```bash
for name in kf2004 kf2204 kf2404 kf2604; do
  echo "== $name =="
  docker logs "$name"
done
```

期望：sshd 已启动；template 检查不应报错。若日志提示需要重新初始化 template，多半是
`/root/images` 被外部挂载遮住了，或镜像构建时未嵌入 template。

## 3. 一键 smoke test

```bash
for name in kf2004 kf2204 kf2404 kf2604; do
  echo "== $name =="
  docker exec "$name" bash -lc '/usr/local/bin/kernel-fuzz-smoke-test'
done
```

期望：

| 检查项 | 期望结果 |
| --- | --- |
| Go | `GOROOT=/root/software/goX.Y.Z`，`GOPATH=/root/software/gopath` |
| GCC/LLVM | 默认来自 `/root/.cvm/toolchains/...` |
| Python | `python` 来自 `/opt/miniforge/envs/kernel-fuzz/bin/python` |
| syzkaller | 存在固定 commit 源码，有 `.git` 和 `Makefile`，没有预编译 `bin/syz-manager` |
| template | `/root/images/image-template` 为 `Ready` |
| sshd | root 登录和密码登录策略存在，但 root 密码仍为 locked |
| `/etc/motd` | 提示 root locked、syzkaller source、guest template key、`.bash_env` 和 proxy 边界 |
| `/usr/local/lib/kernel-fuzz` | final 镜像中不存在 |
| `/root/fuzzers/default-syzkaller-path` | 不存在 |

## 4. 工具链版本核验

```bash
for name in kf2004 kf2204 kf2404 kf2604; do
  echo "== $name =="
  docker exec "$name" bash -lc '
    set -Eeuo pipefail
    printf "go: "; go version
    printf "gcc: "; gcc -dumpfullversion
    printf "clang: "; clang --version | head -n 1
    printf "cmake: "; cmake --version | head -n 1
    printf "python: "; python --version
    printf "conda env: %s\n" "$CONDA_DEFAULT_ENV"
    printf "syzqemuctl: "; syzqemuctl --version | head -n 1
    printf "cvm: "; cvm --version
  '
done
```

期望版本：

| 容器 | GCC | LLVM/Clang | Go | Python | template |
| --- | --- | --- | --- | --- | --- |
| `kf2004` | 12.3.0 | 17.0.6 | 1.24.8 | 3.10 | Bullseye |
| `kf2204` | 13.4.0 | 19.1.7 | 1.24.8 | 3.10 | Bullseye |
| `kf2404` | 14.2.0 | 21.1.8 | 1.26.5 | 3.12 | Trixie |
| `kf2604` | 15.3.0 | 22.1.8 | 1.26.5 | 3.14 | Trixie |

## 5. syzkaller 源码而非预编译产物

逐个确认固定源码目录和 commit：

```bash
for name in kf2004 kf2204 kf2404 kf2604; do
  echo "== $name =="
  docker exec "$name" bash -lc '
    set -Eeuo pipefail
    src=(/root/fuzzers/syzkaller-???????-????????)
    test "${#src[@]}" = 1
    printf "path: %s\n" "${src[0]}"
    git -C "${src[0]}" rev-parse --short=7 HEAD
    test -f "${src[0]}/Makefile"
    test ! -e "${src[0]}/bin/syz-manager"
  '
done
```

可选：只在一个容器中实际构建 syzkaller，确认用户工作流可用。这个步骤会增加该容器 writable
layer 的体积，但不会改变镜像。

```bash
docker exec kf2404 bash -lc '
  set -Eeuo pipefail
  src=(/root/fuzzers/syzkaller-???????-????????)
  cd "${src[0]}"
  make -j"$(nproc)" TARGETOS=linux TARGETARCH=amd64
  test -x bin/syz-manager
  test -x bin/linux_amd64/syz-executor
'
```

## 6. guest image template 与 syzqemuctl

```bash
for name in kf2004 kf2204 kf2404 kf2604; do
  echo "== $name =="
  docker exec "$name" bash -lc '
    set -Eeuo pipefail
    syzqemuctl status image-template
    test -f /root/images/image-template/.syzqemuctl-image.json
  '
done
```

检查 template 分布：

```bash
for name in kf2004 kf2204 kf2404 kf2604; do
  echo "== $name =="
  docker exec "$name" python - <<'PY'
import json
with open("/root/images/image-template/.syzqemuctl-image.json") as f:
    data = json.load(f)
print(data.get("distribution"))
PY
done
```

期望：`kf2004` 和 `kf2204` 为 `bullseye`，`kf2404` 和 `kf2604` 为 `trixie`。

可选：从 template 克隆一个测试 image，再删除。这个步骤主要验证后续实验创建 image 是否足够顺滑：

```bash
docker exec kf2404 bash -lc '
  set -Eeuo pipefail
  syzqemuctl create verification-clone
  syzqemuctl status verification-clone
  syzqemuctl delete verification-clone
'
```

## 7. QEMU/KVM 基础检查

```bash
for name in kf2204 kf2404 kf2604; do
  echo "== $name =="
  docker exec "$name" bash -lc '
    set -Eeuo pipefail
    test -e /dev/kvm
    qemu-system-x86_64 --version
    set +e
    timeout 3 qemu-system-x86_64 -accel kvm -machine none -display none -nodefaults -S
    rc=$?
    set -e
    if [ "$rc" != 124 ]; then
      echo "QEMU/KVM did not stay running until timeout; rc=$rc" >&2
      exit 1
    fi
  '
done
```

期望：命令因 `timeout` 返回 124，表示 QEMU 成功启动并等待；若立即失败，通常是宿主机 KVM
权限、虚拟化开关或 Docker 参数问题。

## 8. kernel headers/libs 与构建依赖

先检查常用命令和开发包是否存在：

```bash
for name in kf2204 kf2404 kf2604; do
  echo "== $name =="
  docker exec "$name" bash -lc '
    set -Eeuo pipefail
    for cmd in make gcc g++ clang ld.lld llvm-ar llvm-objcopy pahole bison flex \
      bc cpio rsync openssl pkg-config zstd lz4 lzop qemu-system-x86_64; do
      command -v "$cmd" >/dev/null
    done
    dpkg-query -W \
      build-essential linux-libc-dev libc6-dev libc6-dev-i386 \
      libelf-dev libdw-dev libssl-dev libncurses-dev libzstd-dev liblz4-dev \
      libbluetooth-dev libcap-dev libunwind-dev protobuf-compiler dwarves \
      btrfs-progs dosfstools f2fs-tools squashfs-tools xfsprogs
  '
done
```

再用一个小程序实际链接几类常见库：

```bash
docker exec kf2404 bash -lc '
  set -Eeuo pipefail
  cat >/tmp/kernel-fuzz-libs.c <<'"'"'EOF'"'"'
#include <elf.h>
#include <gelf.h>
#include <libelf.h>
#include <elfutils/libdw.h>
#include <openssl/ssl.h>
#include <zstd.h>
#include <lz4.h>
#include <bluetooth/bluetooth.h>
int main(void) {
    SSL_library_init();
    ZSTD_versionNumber();
    LZ4_versionNumber();
    return elf_version(EV_CURRENT) == EV_NONE;
}
EOF
  gcc /tmp/kernel-fuzz-libs.c -o /tmp/kernel-fuzz-libs \
    -lelf -ldw -lssl -lcrypto -lzstd -llz4 -lbluetooth
  /tmp/kernel-fuzz-libs
'
```

如果要验证某个 Linux source tree，可以挂载到 `/root/kernels/linux` 后执行：

```bash
docker exec kf2404 bash -lc '
  set -Eeuo pipefail
  cd /root/kernels/linux
  make O=/tmp/kbuild-gcc ARCH=x86_64 defconfig
  make O=/tmp/kbuild-gcc ARCH=x86_64 -j"$(nproc)" olddefconfig prepare modules_prepare
  make O=/tmp/kbuild-llvm ARCH=x86_64 LLVM=1 defconfig
  make O=/tmp/kbuild-llvm ARCH=x86_64 LLVM=1 -j"$(nproc)" olddefconfig prepare modules_prepare
'
```

完整 `bzImage` 或 `modules` 编译建议只在一两个代表性容器中做，否则会消耗大量时间和磁盘。

## 9. SSH 登录验证

root 密码默认 locked，这一点是预期行为：

```bash
docker exec kf2404 passwd -S root
docker exec kf2404 bash -lc '
  /usr/sbin/sshd -T | grep -Fx "permitrootlogin yes"
  /usr/sbin/sshd -T | grep -Fx "passwordauthentication yes"
  /usr/sbin/sshd -T | grep -Fx "permitemptypasswords no"
'
```

手动设置密码后测试 localhost SSH：

```bash
docker exec -it kf2404 passwd
ssh -p 2244 -o StrictHostKeyChecking=accept-new root@127.0.0.1
```

或者使用 authorized keys：

```bash
docker exec kf2404 bash -lc 'mkdir -p /root/.ssh && chmod 700 /root/.ssh'
docker cp ~/.ssh/id_ed25519.pub kf2404:/tmp/agent-key.pub
docker exec kf2404 bash -lc '
  cat /tmp/agent-key.pub >>/root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
'
ssh -p 2244 root@127.0.0.1
```

建议端口始终绑定 `127.0.0.1`，除非宿主机网络边界已经单独审计过。

若只通过 `docker exec` 使用容器，可以验证 sshd 可关闭：

```bash
docker run --rm -d --name kf2404-nossh \
  --privileged \
  -e KERNEL_FUZZ_START_SSHD=0 \
  qgrain/kernel-fuzz:2404_v1 sleep infinity
docker exec kf2404-nossh bash -lc '! pgrep -x sshd'
docker rm -f kf2404-nossh
```

## 10. coding agent 亲和性验证

重点验证非交互 login shell 能加载 `/root/.bash_env`：

```bash
docker exec kf2404 bash -lc '
  set -Eeuo pipefail
  test "$CONDA_DEFAULT_ENV" = kernel-fuzz
  test "$(command -v python)" = /opt/miniforge/envs/kernel-fuzz/bin/python
  test "$(command -v go)" = "$GOROOT/bin/go"
  test "$GOPATH" = /root/software/gopath
  test "$(command -v gcc)" = "/root/.cvm/toolchains/gcc/$(< /root/.cvm/defaults/gcc)/bin/gcc"
  test "$(command -v clang)" = "/root/.cvm/toolchains/llvm/$(< /root/.cvm/defaults/llvm)/bin/clang"
'
```

再验证交互 shell 的提示符：

```bash
docker exec kf2404 bash -ilc '
  test "$CONDA_DEFAULT_ENV" = kernel-fuzz
  [[ $PS1 == "(kernel-fuzz) "* ]]
'
```

如果要模拟 agent 修改宿主机项目，可以额外启动一个带工作区挂载的容器：

```bash
docker run -d --name kf2404-work --hostname kf2404-work --privileged \
  -p 127.0.0.1:2245:22 \
  -v "$PWD":/work \
  -w /work \
  qgrain/kernel-fuzz:2404_v1 sleep infinity

docker exec kf2404-work bash -lc '
  set -Eeuo pipefail
  pwd
  git status --short
  go version
  gcc -dumpfullversion
'
```

## 11. SSH/MOTD banner 建议

不建议把使用说明放到 `sshd_config Banner`。pre-auth banner 会在认证前展示，更适合放法律或安全提示；
这些镜像的使用说明包含路径、工具、proxy 等开发信息，更适合放在登录后的 `/etc/motd`。

镜像内置的 `/etc/motd` 应保持类似如下的简洁信息：

```text
kernel-fuzz Docker image

- Root password is locked by default. Run `passwd` or add authorized_keys before SSH login.
- Pinned syzkaller source is under /root/fuzzers/; build it inside your experiment container.
- Guest template SSH key material under /root/images/image-template is public fuzzing infrastructure.
  Use it only for isolated throwaway VMs; do not rely on it to protect networked or valuable guests.
- Go, cvm, Conda, and compiler paths are loaded from /root/.bash_env for both interactive shells and `bash -lc`.
- No proxy is stored in this image. Pass proxy variables at build or runtime only when needed.
```

这份 MOTD 是登录后的使用须知，不是 pre-auth SSH banner。

## 12. 清理

```bash
docker rm -f kf2004 kf2204 kf2404 kf2604 kf2404-work 2>/dev/null || true
```

建议记录每个 release 的验收结果，包括工具链版本、template distribution、KVM 检查、syzkaller
是否未预编译、SSH 是否可登录，以及是否能通过 `docker exec NAME bash -lc` 获得正确环境。
