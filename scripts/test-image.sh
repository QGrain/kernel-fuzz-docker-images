#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
    echo 'Usage: bash scripts/test-image.sh IMAGE' >&2
    exit 2
fi
image=$1

docker image inspect "$image" | python3 -c '
import json, sys
image = json.load(sys.stdin)[0]
env = image.get("Config", {}).get("Env") or []
proxy = [item for item in env if item.split("=", 1)[0].lower() in {
    "http_proxy", "https_proxy", "all_proxy", "no_proxy"}]
if proxy:
    raise SystemExit("Proxy environment was persisted in the image")
print("Image configuration contains no proxy variables")
'
docker image inspect "$image" | python3 -c '
import json, re, sys
image_ref = sys.argv[1]
image = json.load(sys.stdin)[0]
labels = image.get("Config", {}).get("Labels") or {}
required = [
    "org.opencontainers.image.title",
    "org.opencontainers.image.created",
    "org.opencontainers.image.revision",
    "org.opencontainers.image.source",
    "org.opencontainers.image.version",
    "org.opencontainers.image.ref.name",
    "org.opencontainers.image.licenses",
    "org.opencontainers.image.base.name",
]
missing = [name for name in required if not labels.get(name)]
if missing:
    raise SystemExit("Missing OCI labels: " + ", ".join(missing))
if labels["org.opencontainers.image.source"] != "https://github.com/QGrain/kernel-fuzz-docker-images":
    raise SystemExit("Unexpected OCI source label")
if labels["org.opencontainers.image.title"] != "kernel-fuzz":
    raise SystemExit("Unexpected OCI title label")
if not labels["org.opencontainers.image.base.name"].startswith("ubuntu:"):
    raise SystemExit("OCI base.name should be a digest-qualified Ubuntu image")
if "@sha256:" not in labels["org.opencontainers.image.base.name"]:
    raise SystemExit("OCI base.name is not digest-qualified")
if ":" in image_ref and not image_ref.endswith(":latest"):
    tag = image_ref.rsplit(":", 1)[1]
    if labels["org.opencontainers.image.version"] != tag:
        raise SystemExit("OCI version does not match image tag")
    if labels["org.opencontainers.image.ref.name"] != image_ref:
        raise SystemExit("OCI ref.name does not match image reference")
revision = labels["org.opencontainers.image.revision"]
if not re.fullmatch(r"[0-9a-f]{40}(-dirty)?|unknown", revision):
    raise SystemExit("Unexpected OCI revision format")
print("OCI labels passed")
' "$image"
docker history --no-trunc "$image" | python3 -c '
import sys
history = sys.stdin.read().lower()
if any(name in history for name in ("http_proxy", "https_proxy", "all_proxy")):
    raise SystemExit("Proxy setting appears in image history")
print("Image history contains no proxy settings")
'
container=$(docker run --rm -d "$image" sleep infinity)
trap 'docker stop "$container" >/dev/null 2>&1 || true' EXIT

# Exercise the real entrypoint, then the exact non-interactive login-shell path
# used by coding agents through `docker exec`.
docker exec "$container" bash -lc '/usr/local/bin/kernel-fuzz-smoke-test'
docker exec "$container" bash -ilc '
    test "$CONDA_DEFAULT_ENV" = kernel-fuzz
    [[ $PS1 == "(kernel-fuzz) "* ]]
'
docker exec "$container" bash -lc '
    pgrep -x sshd >/dev/null
    /usr/sbin/sshd -T | grep -Fxq "permitrootlogin yes"
    /usr/sbin/sshd -T | grep -Fxq "passwordauthentication yes"
    /usr/sbin/sshd -T | grep -Fxq "permitemptypasswords no"
    printf "int main(void) { return 0; }\n" | gcc -x c - -o /tmp/kernel-fuzz-gcc-test
    /tmp/kernel-fuzz-gcc-test
    printf "int main(void) { return 0; }\n" | clang -x c - -o /tmp/kernel-fuzz-clang-test
    /tmp/kernel-fuzz-clang-test
'
echo 'Entrypoint, SSH policy, login shell, GCC, and Clang passed'
