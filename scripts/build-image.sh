#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    echo 'Usage: bash scripts/build-image.sh {2004_v2|2204_v3|2404_v1|2604_v1} [all|release-base|final|base|tooling|compilers]' >&2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
    exit 2
fi
tag=$1
target=${2:-all}
case "$tag" in
    2004_v2|2204_v3|2404_v1|2604_v1) ;;
    *) usage; exit 2 ;;
esac
case "$target" in
    all|release-base|final|base|tooling|compilers) ;;
    *) usage; exit 2 ;;
esac

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
image="qgrain/kernel-fuzz:$tag"
# This is deliberately a local-only implementation tag, not a Docker Hub tag.
# It makes the expensive compiler stage reusable by the final image build.
release_base_image="kernel-fuzz-build:${tag}-base"
oci_source=${KERNEL_FUZZ_OCI_SOURCE:-https://github.com/QGrain/kernel-fuzz-docker-images}
oci_revision=$(git -C "$repo_root" rev-parse --verify HEAD 2>/dev/null || printf unknown)
if [[ $oci_revision != unknown ]]; then
    if ! git -C "$repo_root" diff --quiet \
        || ! git -C "$repo_root" diff --cached --quiet \
        || [[ -n $(git -C "$repo_root" ls-files --others --exclude-standard) ]]; then
        oci_revision="${oci_revision}-dirty"
    fi
fi
if [[ -n ${SOURCE_DATE_EPOCH:-} ]]; then
    oci_created=$(date -u -d "@$SOURCE_DATE_EPOCH" '+%Y-%m-%dT%H:%M:%SZ')
else
    oci_created=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
fi

build_args=()
build_args+=(
    --build-arg "OCI_CREATED=$oci_created"
    --build-arg "OCI_REVISION=$oci_revision"
    --build-arg "OCI_SOURCE=$oci_source"
    --build-arg "OCI_VERSION=$tag"
    --build-arg "OCI_REF_NAME=$image"
)
for name in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY; do
    if [[ -n ${!name:-} ]]; then
        build_args+=(--build-arg "$name")
    fi
done
for name in CVM_JOBS; do
    if [[ -n ${!name:-} ]]; then
        if [[ ! ${!name} =~ ^[1-9][0-9]*$ ]]; then
            echo "$name must be a positive integer" >&2
            exit 2
        fi
        build_args+=(--build-arg "$name=${!name}")
    fi
done

no_cache_args=()
case "${KERNEL_FUZZ_NO_CACHE:-0}" in
    0|false|False|FALSE|no|No|NO|'') ;;
    1|true|True|TRUE|yes|Yes|YES)
        no_cache_args+=(--no-cache)
        ;;
    *)
        echo 'KERNEL_FUZZ_NO_CACHE must be 0/1, false/true, or yes/no' >&2
        exit 2
        ;;
esac

build_target() {
    local docker_target=$1
    local output_image=$2
    docker buildx build --load --platform linux/amd64 \
        "${no_cache_args[@]}" \
        --progress=plain --target "$docker_target" \
        --build-arg "RELEASE_BASE_IMAGE=$release_base_image" \
        "${build_args[@]}" \
        -f "$repo_root/dockerfiles/Dockerfile_$tag" \
        -t "$output_image" "$repo_root"
    echo "Built $output_image (target: $docker_target)"
}

built_final=0
case "$target" in
    all)
        build_target compilers "$release_base_image"
        build_target final "$image"
        built_final=1
        ;;
    release-base)
        build_target compilers "$release_base_image"
        ;;
    final)
        if ! docker image inspect "$release_base_image" >/dev/null 2>&1; then
            echo "Missing $release_base_image; build it first with:" >&2
            echo "  bash scripts/build-image.sh $tag release-base" >&2
            exit 1
        fi
        build_target final "$image"
        built_final=1
        ;;
    *)
        build_target "$target" "kernel-fuzz-test:${tag}-${target}"
        ;;
esac

if [[ $built_final == 1 && ${KERNEL_FUZZ_EMBED_TEMPLATE:-1} == 1 ]]; then
    template_source=
    case "$tag" in
        2004_v2|2204_v3) distribution=bullseye ;;
        2404_v1|2604_v1) distribution=trixie ;;
    esac
    candidates=("kernel-fuzz-template-cache:$distribution")
    case "$tag" in
        2004_v2) candidates+=(qgrain/kernel-fuzz:2204_v3) ;;
        2204_v3) candidates+=(qgrain/kernel-fuzz:2004_v2) ;;
        2404_v1) candidates+=(qgrain/kernel-fuzz:2604_v1) ;;
        2604_v1) candidates+=(qgrain/kernel-fuzz:2404_v1) ;;
    esac
    for candidate in "${candidates[@]}"; do
        if ! docker image inspect "$candidate" >/dev/null 2>&1; then
            continue
        fi
        candidate_distribution=$(docker run --rm --entrypoint /usr/bin/python3 \
            "$candidate" -c '
import json
try:
    with open("/root/images/image-template/.syzqemuctl-image.json") as stream:
        print(json.load(stream)["distribution"])
except (FileNotFoundError, KeyError, json.JSONDecodeError):
    pass
' 2>/dev/null || true)
        if [[ $candidate_distribution == "$distribution" ]]; then
            template_source=$candidate
            break
        fi
    done
    if [[ -n $template_source ]]; then
        bash "$repo_root/scripts/embed-template.sh" \
            "$image" "$distribution" "$template_source"
    else
        bash "$repo_root/scripts/embed-template.sh" "$image" "$distribution"
    fi
    docker tag "$image" "kernel-fuzz-template-cache:$distribution"
fi
