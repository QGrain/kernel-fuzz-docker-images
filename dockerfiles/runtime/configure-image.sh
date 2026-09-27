#!/usr/bin/env bash
set -Eeuo pipefail

config_dir=/tmp/kernel-fuzz-config
install -m 0644 "$config_dir/bash_env" /root/.bash_env
install -m 0644 "$config_dir/vimrc" /root/.vimrc
install -m 0644 "$config_dir/screenrc" /root/.screenrc
install -m 0644 "$config_dir/tmux.conf" /root/.tmux.conf
install -m 0644 "$config_dir/motd" /etc/motd
install -m 0644 "$config_dir/sshd-kernel-fuzz.conf" \
    /etc/ssh/sshd_config.d/50-kernel-fuzz.conf

for profile in /root/.profile /root/.bashrc; do
    if ! grep -Fq '[ -f "$HOME/.bash_env" ] && . "$HOME/.bash_env"' "$profile"; then
        sed -i '1i [ -f "$HOME/.bash_env" ] && . "$HOME/.bash_env"' "$profile"
    fi
done

# .bash_env must run before .bashrc's non-interactive early return, but the
# stock interactive .bashrc assigns PS1 later and overwrites Conda's prefix.
# Refresh only the prompt after the rest of .bashrc has finished.
cat >>/root/.bashrc <<'EOF'

# Refresh the prompt after the stock .bashrc has assigned PS1.
if [[ $- == *i* ]] && [[ ${CONDA_DEFAULT_ENV:-} == kernel-fuzz ]]; then
    conda activate kernel-fuzz
fi
EOF

chmod 0755 /usr/local/bin/kernel-fuzz-entrypoint
chmod 0755 /usr/local/bin/kernel-fuzz-init-template
chmod 0755 /usr/local/bin/kernel-fuzz-smoke-test
test -x /root/.cvm/bin/cvm
test -x /opt/miniforge/envs/kernel-fuzz/bin/syzqemuctl
