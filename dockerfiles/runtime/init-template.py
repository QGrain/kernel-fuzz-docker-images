#!/opt/miniforge/envs/kernel-fuzz/bin/python
"""Create the default x86_64 syzqemuctl template on first privileged start."""

import os
import sys

from syzqemuctl import ImageManager, global_conf


def main() -> int:
    images_home = os.environ.get("SYZ_IMAGES_HOME", "/root/images")
    distribution = os.environ.get("SYZ_TEMPLATE_DISTRIBUTION", "trixie")
    size = int(os.environ.get("SYZ_TEMPLATE_SIZE_MB", "3072"))

    if not global_conf.is_initialized():
        global_conf.initialize(images_home, force=False)
    else:
        global_conf.load()
        images_home = global_conf.images_home or images_home

    manager = ImageManager(images_home, verbose=True)
    if manager.is_image_ready("image-template"):
        print(f"syzqemuctl template ready: {images_home}/image-template")
        return 0
    if not os.path.exists("/dev/loop-control"):
        print(
            "Template is missing and /dev/loop-control is unavailable; start the "
            "container with --privileged to create it.",
            file=sys.stderr,
        )
        return 1
    if not manager.initialize(blocking=True, distribution=distribution, size=size):
        print(
            "Template initialization failed; inspect the image directory before "
            "retrying or using --force.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
