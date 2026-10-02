#!/usr/bin/env bash
set -Eeuo pipefail
[ -f /root/.bash_env ] && . /root/.bash_env

test "$(id -u)" = 0
[[ $GOROOT == /root/software/go[0-9]* ]]
test "$(command -v go)" = "$GOROOT/bin/go"
test "$GOPATH" = /root/software/gopath
test "$(command -v python)" = /opt/miniforge/envs/kernel-fuzz/bin/python
test "$(command -v fzf)" = /root/.fzf/bin/fzf
fzf --version | grep -Eq '^[0-9]+[.][0-9]+[.]'
test "$(command -v gcc)" = "/root/.cvm/toolchains/gcc/$(< /root/.cvm/defaults/gcc)/bin/gcc"
test "$(command -v clang)" = "/root/.cvm/toolchains/llvm/$(< /root/.cvm/defaults/llvm)/bin/clang"
test -x /usr/bin/qemu-system-x86_64
for tool in lz4 lzop zstd; do command -v "$tool" >/dev/null; done
syzkaller_roots=(/root/fuzzers/syzkaller-???????-????????)
test "${#syzkaller_roots[@]}" = 1
test -f "${syzkaller_roots[0]}/Makefile"
test -d "${syzkaller_roots[0]}/.git"
test ! -e "${syzkaller_roots[0]}/bin/syz-manager"
test ! -e /root/fuzzers/default-syzkaller-path
test ! -e /usr/local/lib/kernel-fuzz
test -d /root/images/image-template
template_status=$(syzqemuctl status image-template)
grep -Fq 'Ready' <<<"$template_status"
grep -Fiq "$SYZ_TEMPLATE_DISTRIBUTION" <<<"$template_status"
test -x /usr/local/bin/pwndbg
gdb --version >/dev/null
pwndbg --version >/dev/null
test -x /root/.cvm/bin/cvm
test -e /root/.screenrc
test -e /root/.tmux.conf
test -e /root/.vimrc
test -e /root/.bash_env
loader='[ -f "$HOME/.bash_env" ] && . "$HOME/.bash_env"'
test "$(head -n 1 /root/.profile)" = "$loader"
test "$(head -n 1 /root/.bashrc)" = "$loader"
test "$(passwd -S root | awk '{print $2}')" = L
grep -Fxq 'PermitRootLogin yes' /etc/ssh/sshd_config.d/50-kernel-fuzz.conf
grep -Fxq 'PasswordAuthentication yes' /etc/ssh/sshd_config.d/50-kernel-fuzz.conf
grep -Fq 'QEMU images for kernel testing are managed by syzqemuctl' /etc/motd
grep -Fq 'refer https://github.com/QGrain/syzqemuctl for details' /etc/motd
grep -Fq 'refer https://github.com/QGrain/cvm' /etc/motd
grep -Fq 'No proxy is stored in this image' /etc/motd
printf 'go=%s\n' "$(go version)"
printf 'gcc=%s\n' "$(gcc -dumpfullversion)"
printf 'clang=%s\n' "$(clang --version | head -n 1)"
printf 'python=%s\n' "$(python --version)"
printf 'fzf=%s\n' "$(fzf --version)"
printf 'syzqemuctl=%s\n' "$(syzqemuctl --version | head -n 1)"
