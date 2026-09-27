#!/usr/bin/env bash
set -Eeuo pipefail
: "${GCC_VERSION:?}" "${CVM_JOBS:?}"
export CVM_HOME=/root/.cvm
export PATH="/opt/cmake/bin:$CVM_HOME/bin:$PATH"
cd /root/software
cvm install gcc "$GCC_VERSION" --jobs "$CVM_JOBS"
cvm alias default gcc "$GCC_VERSION"
test -x "$CVM_HOME/toolchains/gcc/$GCC_VERSION/bin/gcc"
