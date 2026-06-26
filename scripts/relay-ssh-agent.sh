#!/bin/bash
# Relay the Windows SSH agent (Bitwarden / OpenSSH) into WSL via npiperelay.
# npiperelay.exe is launched through WSL interop, which is tied to the session
# that started socat. When that session dies the interop socket goes away and
# the detached socat keeps listening but can no longer spawn a working relay.
# So we must verify the agent actually responds, not just that a socket exists.

export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"

__is_wsl || return 0 2>/dev/null || exit 0

# Returns 0 if the agent socket is alive and talking, 1 otherwise.
# ssh-add -l: exit 0 = keys listed, exit 1 = empty agent OR broken relay
# (distinguish via the message), exit 2 = cannot connect at all.
__ssh_agent_ok() {
    local out
    out="$(ssh-add -l 2>&1)"
    case "$?" in
        0) return 0 ;;
        1) [[ "$out" == *"no identities"* ]] && return 0 || return 1 ;;
        *) return 1 ;;
    esac
}

if ! __ssh_agent_ok; then
    pkill -f "socat UNIX-LISTEN:${SSH_AUTH_SOCK}" 2>/dev/null
    rm -f "$SSH_AUTH_SOCK"
    (setsid socat UNIX-LISTEN:"$SSH_AUTH_SOCK",fork EXEC:"npiperelay.exe -ei -s //./pipe/openssh-ssh-agent",nofork &) >/dev/null 2>&1
fi
