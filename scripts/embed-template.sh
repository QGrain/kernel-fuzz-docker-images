#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo 'Usage: bash scripts/embed-template.sh IMAGE {bullseye|trixie} [TEMPLATE_IMAGE]' >&2
    exit 2
fi
image=$1
distribution=$2
template_image=${3:-}
case "$distribution" in
    bullseye|trixie) ;;
    *) echo 'Distribution must be bullseye or trixie' >&2; exit 2 ;;
esac

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

if [[ -n $template_image ]]; then
    actual_distribution=$(docker run --rm --entrypoint /usr/bin/python3 \
        "$template_image" -c '
import json
with open("/root/images/image-template/.syzqemuctl-image.json") as stream:
    print(json.load(stream)["distribution"])
')
    if [[ $actual_distribution != "$distribution" ]]; then
        echo "$template_image contains $actual_distribution, expected $distribution" >&2
        exit 1
    fi
    docker buildx build --load --platform linux/amd64 --progress=plain \
        --build-arg "BASE_IMAGE=$image" \
        --build-arg "TEMPLATE_IMAGE=$template_image" \
        -f "$repo_root/dockerfiles/Dockerfile_template_from_image" \
        -t "$image" "$repo_root"
    echo "Embedded $distribution image-template from $template_image in $image"
    exit 0
fi

template_tmp=$(mktemp -d)
cleanup() {
    if [[ -n ${template_tmp:-} && -d $template_tmp ]]; then
        docker run --rm \
            -v "$template_tmp:/data" \
            --entrypoint chown "$image" \
            -R "$(id -u):$(id -g)" /data >/dev/null 2>&1 || true
        rm -rf -- "$template_tmp"
    fi
}
trap cleanup EXIT

runtime_args=()
for name in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY; do
    if [[ -n ${!name:-} ]]; then
        runtime_args+=(-e "$name")
    fi
done

echo "Generating $distribution image-template for $image"
generated=0
for attempt in 1 2 3; do
    if docker run --rm --privileged --platform linux/amd64 \
        "${runtime_args[@]}" \
        -e "SYZ_TEMPLATE_DISTRIBUTION=$distribution" \
        -e "TEMPLATE_HOST_UID=$(id -u)" \
        -e "TEMPLATE_HOST_GID=$(id -g)" \
        -v "$template_tmp:/root/images" \
        --entrypoint /bin/bash "$image" -c '
            set -Eeuo pipefail
            trap '\''chown -R "$TEMPLATE_HOST_UID:$TEMPLATE_HOST_GID" /root/images'\'' EXIT
            cat >/tmp/kernel-fuzz-wgetrc <<'\''EOF'\''
timeout = 60
tries = 5
retry_connrefused = on
EOF
            export WGETRC=/tmp/kernel-fuzz-wgetrc
            /usr/local/bin/kernel-fuzz-init-template
        '; then
        generated=1
        break
    fi
    echo "Template generation failed (attempt $attempt/3)" >&2
    find "$template_tmp" -mindepth 1 -depth -delete
    if [[ $attempt != 3 ]]; then
        sleep 2
    fi
done
test "$generated" = 1
test -d "$template_tmp/image-template"

# The proxy is supplied only to the temporary generator container above. This
# final layer build has no proxy build arguments and therefore cannot persist it.
docker buildx build --load --platform linux/amd64 --progress=plain \
    --build-arg "BASE_IMAGE=$image" \
    -f "$repo_root/dockerfiles/Dockerfile_template" \
    -t "$image" "$template_tmp"
echo "Embedded $distribution image-template in $image"
