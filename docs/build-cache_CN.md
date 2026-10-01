# kernel-fuzz 构建缓存与增量迭代说明

本项目把镜像拆成两个发布相关边界：

| 边界 | 本地 tag | 作用 | 是否推送 |
| --- | --- | --- | --- |
| release-base | `kernel-fuzz-build:<tag>-base` | OS 包、Go、CMake、Miniforge、cvm、GCC/LLVM 等昂贵环境 | 不推送 |
| final | `qgrain/kernel-fuzz:<tag>` | syzkaller 源码、fzf、运行时配置、banner、shell 配置、guest template、OCI labels | 发布对象 |

常规迭代应优先执行：

```bash
bash scripts/build-image.sh 2404_v1 final
```

只有确实改变基础环境或工具链时，才执行：

```bash
CVM_JOBS=32 bash scripts/build-image.sh 2404_v1 release-base
bash scripts/build-image.sh 2404_v1 final
```

发布验收前如需故意丢弃 Docker layer cache，可加：

```bash
KERNEL_FUZZ_NO_CACHE=1 CVM_JOBS=32 bash scripts/build-image.sh 2404_v1 release-base
KERNEL_FUZZ_NO_CACHE=1 bash scripts/build-image.sh 2404_v1 final
```

这会让 BuildKit 对镜像层使用 `--no-cache`；`RUN --mount=type=cache` 的下载/源码缓存仍可复用。

## 为什么改一点脚本有时仍会重编译 GCC/LLVM？

Docker layer cache 是按 Dockerfile 指令、复制进去的文件内容、build args 和父层 digest 计算的。
当前 `compilers` target 基于 `base` 和 `tooling`：

```text
Ubuntu digest
  -> base: install-base.sh
  -> tooling: install-tooling.sh
  -> compilers: install-compilers.sh / install-gcc.sh / install-llvm.sh
  -> final: syzkaller + fzf + runtime config + labels
```

因此，如果修改的是 `install-base.sh`、`install-tooling.sh` 或 Ubuntu digest，后面的 compiler layer
父层已经变化，执行 `release-base` 时就会重新跑 `cvm install gcc/llvm`。这并不是中间 base 失效，
而是本次改动确实位于 GCC/LLVM 构建之前。

`RUN --mount=type=cache,target=/root/.cvm/cache` 和 `/root/software` 主要复用下载包、源码包和部分构建输入，
可以减少网络和准备时间；但它不保证直接复用最终安装好的 `/root/.cvm/toolchains/<kind>/<version>`。
所以源码缓存命中时仍可能重新编译。

## 怎样避免不必要的重编译？

1. 只改 final 层内容时，直接执行 `bash scripts/build-image.sh <tag> final`。
2. 不要用 `all` 作为默认肌肉记忆；`all` 等价于先重建 `release-base` 再重建 final。
3. 改 README/docs 不需要构建镜像；如果为了更新 OCI revision，要先 commit，再重建 final。
4. 改 banner、vimrc、tmux、screen、entrypoint、smoke test、syzkaller pin、fzf ref，通常只需要重建 final。
5. 改 apt 包、Go/CMake/Miniforge/cvm、GCC/LLVM 版本或 Ubuntu digest，才重建 release-base。

本仓库的 final stage 把 OCI labels 放在较靠后的层，避免每次 `OCI_CREATED` 改变都使 syzkaller
源码和运行时配置层失效。这样从同一个 `kernel-fuzz-build:<tag>-base` 重建 final 会更快。
