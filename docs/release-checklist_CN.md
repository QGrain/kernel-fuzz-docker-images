# kernel-fuzz 发布前检查清单

这份清单记录从源码到 Docker Hub 发布前的最小流程。最后的 `git push` 和 `docker push`
应由维护者亲自执行。

## 1. 源码状态

```bash
git status --short
bash -n scripts/*.sh dockerfiles/build/*.sh dockerfiles/runtime/*.sh
rg -n 'FROM ubuntu:[0-9]' dockerfiles && exit 1 || true
```

期望：工作树干净；Shell 语法通过；Dockerfile 中没有未 pin digest 的 `FROM ubuntu:<release>`。

## 2. 从干净 commit 构建

```bash
for tag in 2004_v2 2204_v3 2404_v1 2604_v1; do
  CVM_JOBS="${CVM_JOBS:-32}" bash scripts/build-image.sh "$tag" release-base
  bash scripts/build-image.sh "$tag" final
  bash scripts/test-image.sh "qgrain/kernel-fuzz:$tag"
done
docker tag qgrain/kernel-fuzz:2404_v1 qgrain/kernel-fuzz:latest
bash scripts/test-image.sh qgrain/kernel-fuzz:latest
```

`release-base` 会重建昂贵的编译器缓存层；只有修改 OS packages、Go、CMake、Miniforge、cvm、GCC/LLVM
或 Ubuntu digest 时才需要重跑。只改 final 层时，可以只执行 `final`。

## 3. OCI provenance

```bash
for tag in 2004_v2 2204_v3 2404_v1 2604_v1 latest; do
  echo "== $tag =="
  docker image inspect "qgrain/kernel-fuzz:$tag" \
    --format 'version={{ index .Config.Labels "org.opencontainers.image.version" }} revision={{ index .Config.Labels "org.opencontainers.image.revision" }} source={{ index .Config.Labels "org.opencontainers.image.source" }} base={{ index .Config.Labels "org.opencontainers.image.base.name" }}'
done
```

期望：`revision` 是待发布 commit；非 `latest` 的 `version` 与 tag 一致；`base` 为
digest-qualified Ubuntu image。`latest` 是 `2404_v1` 的本地别名，允许 `version=2404_v1`。

## 4. 已知边界

Ubuntu base image 已 pin 到 amd64 manifest digest，但 apt 包和 Debian guest packages 仍在构建时解析；
这保证的是基础 rootfs 不漂移，不是 bit-for-bit 的全栈复现。

20.04 镜像是旧内核兼容镜像，不作为新实验默认推荐。

内置 guest template 包含公开的 fuzzing VM SSH key material，例如 `disk.id_rsa`。它只适合隔离的
throwaway VM，不能保护联网或有价值的 guest。

sshd 默认启动以方便容器登录；root 密码默认 locked。只通过 `docker exec` 使用时，可以设置
`KERNEL_FUZZ_START_SSHD=0`。

## 5. 维护者发布动作

```bash
git push origin main
docker login -u qgrain
for tag in 2004_v2 2204_v3 2404_v1 2604_v1 latest; do
  docker push "qgrain/kernel-fuzz:$tag"
done
```

发布后用 `docker buildx imagetools inspect qgrain/kernel-fuzz:<tag>` 检查公开 tag 是否可解析。
