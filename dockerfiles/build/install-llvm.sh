#!/usr/bin/env bash
set -Eeuo pipefail
: "${LLVM_VERSION:?}" "${CVM_JOBS:?}" "${CVM_LLVM_PROFILE:?}"
export CVM_HOME=/root/.cvm
export PATH="/opt/cmake/bin:$CVM_HOME/bin:$PATH"
cd /root/software
cvm install llvm "$LLVM_VERSION" --jobs "$CVM_JOBS" \
    --profile "$CVM_LLVM_PROFILE"
cvm alias default llvm "$LLVM_VERSION"
test -x "$CVM_HOME/toolchains/llvm/$LLVM_VERSION/bin/clang"
