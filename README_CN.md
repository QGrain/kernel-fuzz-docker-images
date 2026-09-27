# Kernel fuzzing Docker images

[English](README.md) | 中文

[![Docker Hub pulls](https://img.shields.io/docker/pulls/qgrain/kernel-fuzz?logo=docker&label=Docker%20Hub%20pulls)](https://hub.docker.com/r/qgrain/kernel-fuzz)
[![Docker image size](https://img.shields.io/docker/image-size/qgrain/kernel-fuzz/latest?logo=docker&label=latest%20image%20size)](https://hub.docker.com/r/qgrain/kernel-fuzz/tags)
[![License](https://img.shields.io/github/license/QGrain/kernel-fuzz-docker-images)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-linux%2Famd64-0db7ed?logo=docker)](https://hub.docker.com/r/qgrain/kernel-fuzz)

这是 `qgrain/kernel-fuzz` 的版本化 Dockerfile 仓库，目标是为 x86_64
Linux kernel fuzzing 提供可复现的 QEMU/KVM 实验环境。镜像使用
[cvm 0.1.2](https://github.com/QGrain/cvm/releases/tag/v0.1.2) 管理 GCC/LLVM
编译器，使用 [syzqemuctl 0.4.0](https://github.com/QGrain/syzqemuctl/tree/v0.4.0)
管理 guest image。Ubuntu tag 表示容器用户态版本，不表示待测 kernel 版本；待测 kernel
运行在 QEMU guest 中。ARM64/Android guest 支持暂时搁置。

| Docker Hub tag | Ubuntu | cvm GCC | cvm LLVM (`X86`) | Go | Conda 默认激活 Python | 预置 syzkaller 源码 |
| --- | --- | --- | --- | --- | --- | --- |
| `2004_v2` | 20.04 | 12.3.0 | 17.0.6 | 1.24.8 | 3.10 | `6e83b42` (2025-06-30) |
| `2204_v3` | 22.04 | 13.4.0 | 19.1.7 | 1.24.8 | 3.10 | `6e83b42` (2025-06-30) |
| `2404_v1` | 24.04 | 14.2.0 | 21.1.8 | 1.26.5 | 3.12 | `544adce` (2026-07-23) |
| `2604_v1` | 26.04 | 15.3.0 | 22.1.8 | 1.26.5 | 3.14 | `544adce` (2026-07-23) |

`latest` 计划指向兼容性和可靠性更均衡的 `2404_v1`。`2004_v2` 作为旧内核实验兼容镜像保留；
新实验默认推荐使用 `2404_v1`，除非明确需要较老用户态。

## 仓库结构与镜像分层

```text
dockerfiles/
  Dockerfile_<tag>              四个正式 release 定义
  build/                        只复制进构建阶段的脚本
    config/llvm-22.toml          LLVM 22/cvm 兼容性配置
  runtime/                      最终镜像保留的轻量运行时命令
  config/                       shell、编辑器、sshd 配置
scripts/                        宿主机侧构建、模板嵌入、测试脚本
docs/                           更详细的操作文档
```

每个 release Dockerfile 都以 digest-qualified 的 Ubuntu 基础镜像为起点，并分为
`base`、`tooling`、`compilers`、`final` 四个主要阶段。`base` 安装系统包和内核构建常用
headers/libs，`tooling` 安装 Go、CMake、Miniforge、cvm 和 syzqemuctl，`compilers` 通过
cvm 安装 GCC/LLVM。这个昂贵的编译器阶段会在本地标记为
`kernel-fuzz-build:<tag>-base`，随后 `final` 基于它加入固定 commit 的 syzkaller
源码、运行时配置和默认 guest image template。Ubuntu manifest digest 已固定，能避免
`FROM ubuntu:<release>` 随时间漂移；但 apt 包和 Debian guest packages 仍在构建时解析，因此这不是
bit-for-bit 的 package-level 可复现构建。

`kernel-fuzz-build:*` 是本机增量构建用的缓存边界，不是公开产品，不建议推送到 Docker Hub。
它没有独立兼容性承诺；真正发布的仍然只有 `qgrain/kernel-fuzz:<tag>` 和
`qgrain/kernel-fuzz:latest`。如果以后需要远端加速，更合适的方式是使用 registry cache
或私有 CI cache，而不是把 `_base` 当成用户可见 release。

`2604_v1` 额外使用 `dockerfiles/build/config/llvm-22.toml`。这是因为 cvm 0.1.2
默认构建 LLVM 22 时，project/runtime 组合会重复生成 CMake target `check-builtins`。
该配置只保留 X86 后端、`clang`/`lld` 项目，并把 `compiler-rt` 作为 runtime 构建。
它是一个很窄的兼容性修正，只复制进编译器构建阶段，最终镜像中不会保留。

## 镜像内环境

所有镜像都安装 Miniforge 26.7.2。Miniforge 支持常规的 `conda create`、
`conda activate` 等命令，默认 channel 为 conda-forge。自动激活的环境名为
`kernel-fuzz`，其中 Python 版本见上表。

Go 安装在 `/root/software/goX.Y.Z`，`GOPATH=/root/software/gopath`。预置 syzkaller
源码位于 `/root/fuzzers/syzkaller-7bitHASH-YYYYMMDD`。镜像构建时不会执行
`make`，因此默认没有 `bin/syz-manager`；用户应在具体实验容器中按目标架构和配置自行构建。
待测 kernel 也同理，不预编译进镜像。

公共开发环境变量集中在 `/root/.bash_env`。`/root/.profile` 和 `/root/.bashrc`
会在开头加载它，并且 `.bashrc` 的加载语句位于非交互 early-return 之前。因此人工登录 shell
和 coding agent 常用的 `docker exec NAME bash -lc 'CMD'` 都能拿到同一套 Go、cvm、Conda
环境。构建期脚本不会留在 `/usr/local/lib/kernel-fuzz`；最终镜像只保留
`/usr/local/bin/kernel-fuzz-*` 等运行时命令。

## 本地构建

构建需要 Docker BuildKit，并且每个 release 的编译器阶段都需要较大的磁盘空间。Dockerfile
不会写入任何代理变量。如果宿主机需要代理，只在构建命令执行期间传递 Docker 预定义 proxy 变量：

```bash
export http_proxy='http://YOUR_PROXY_HOST:PORT'
export https_proxy="$http_proxy"
export HTTP_PROXY="$http_proxy"
export HTTPS_PROXY="$http_proxy"
CVM_JOBS=32 bash scripts/build-image.sh 2404_v1
bash scripts/test-image.sh qgrain/kernel-fuzz:2404_v1
```

`CVM_JOBS` 默认值为 16；如果 CPU 和内存足够，可以在执行时覆盖为 32 或 48。现在没有
`SYZKALLER_JOBS`，因为 syzkaller 不再在构建镜像时编译。

推荐的增量构建方式如下：

```bash
# 首次构建，或修改 OS 包、Go、CMake、Miniforge、cvm/GCC/LLVM 版本后执行。
CVM_JOBS=32 bash scripts/build-image.sh 2404_v1 release-base

# 只修改 syzkaller pin、运行时配置、README 以外的 final 层内容后执行。
bash scripts/build-image.sh 2404_v1 final

# 同时构建 release-base 和 final；不指定第二个参数时默认如此。
CVM_JOBS=32 bash scripts/build-image.sh 2404_v1 all
```

`final` 目标要求本机已经存在对应的 `kernel-fuzz-build:<tag>-base`，不会悄悄重建它。
这能让“是否重建昂贵编译器层”成为一个明确决策。final 镜像最后会嵌入
`/root/images/image-template`：20.04/22.04 使用 Bullseye，24.04/26.04 使用 Trixie。
本地模板缓存 tag 为 `kernel-fuzz-template-cache:{bullseye,trixie}`。只有在开发一个故意不带
guest template 的镜像时，才应设置 `KERNEL_FUZZ_EMBED_TEMPLATE=0`。

当前流程只保留本地镜像，不会 push。正式 release 应从干净 Git commit 重建，这样最终镜像会带有可追溯的
OCI provenance labels：

```bash
git status --short
CVM_JOBS=32 bash scripts/build-image.sh 2404_v1 release-base
bash scripts/build-image.sh 2404_v1 final
bash scripts/test-image.sh qgrain/kernel-fuzz:2404_v1
docker image inspect qgrain/kernel-fuzz:2404_v1 \
  --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}'
docker tag qgrain/kernel-fuzz:2404_v1 qgrain/kernel-fuzz:latest
```

如果未来要发布到 Docker Hub，应先在仓库外部完成 `docker login -u qgrain`，再显式 push
正式 tag 和 `latest`。`kernel-fuzz-build:*` 不参与发布。

## 运行容器

常用开发容器可以这样启动：

```bash
docker run -d --name kernel-fuzz \
  --privileged \
  -p 127.0.0.1:2222:22 \
  -v /HOST/PATH/KERNELS:/root/kernels \
  qgrain/kernel-fuzz:2404_v1 sleep infinity

docker exec -it kernel-fuzz bash
```

`--privileged` 是 syzqemuctl 初始化 guest image 和使用宿主机 KVM 的常见要求。entrypoint
会启动 sshd，并检查嵌入的 `image-template`。如果用户把空目录或 volume 挂载到
`/root/images`，会遮住镜像内置模板；entrypoint 会尝试重新初始化模板，这时需要容器运行时具备
Debian 访问能力以及必要的运行时代理。模板生成后建议复用同一个 volume。

root 密码默认处于 locked 状态。若需要密码 SSH，容器启动后执行
`docker exec -it kernel-fuzz passwd`；也可以由用户自行写入
`/root/.ssh/authorized_keys`。建议 SSH 端口只绑定到 `127.0.0.1`。不要把代理写入
`.bash_env` 或镜像层；确实需要时用 `docker run -e http_proxy -e https_proxy -e no_proxy`
临时传入。若只需要本地 `docker exec`，可设置 `KERNEL_FUZZ_START_SSHD=0` 跳过 sshd 启动。

内置 syzqemuctl guest template 包含用于一次性 fuzzing VM 登录的 SSH key material，包括
`disk.id_rsa`。它应被视为公开的实验基础设施，只能用于隔离的 throwaway VM，不能用于保护联网或有价值的
guest。

完整的人工验收步骤见
[中文人工验证清单](docs/manual-verification_CN.md)，其中覆盖工具链、guest template、KVM、
kernel headers/libs、SSH、以及 coding agent 的 `bash -lc` 操作亲和性。

## 兼容性边界

目标覆盖 x86_64 主流 LTS 5.x/6.x、Linux 7.x 和当前 mainline。镜像提供构建依赖和默认工具链，
但不承诺某一个 GCC/LLVM 版本能无补丁编译所有历史 kernel。遇到旧 kernel 拒绝新编译器时，
应使用 cvm 选择更合适的编译器版本；遇到特别新的 BTF/Rust-for-Linux 等配置，也可能需要补充
pahole、rust 工具链或禁用相关配置。

2026 年 pin 的 syzkaller 声明 Go 1.26.0，2025 年 pin 的 syzkaller 声明 Go 1.23.7。
20.04/22.04 镜像使用 Go 1.24.8 来服务 2025 年 pin；若要在这些镜像中构建更新的 syzkaller，
可能需要先通过 cvm 或手动方式安装更新的 Go。
