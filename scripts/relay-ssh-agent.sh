#!/bin/bash
export SSH_AUTH_SOCK=$HOME/.ssh/agent.sock

# Check if the socket already exists
ss -a | grep -q $SSH_AUTH_SOCK
if [ $? -ne 0 ]; then
    # Start a new socat process
    rm -f $SSH_AUTH_SOCK
    (setsid socat UNIX-LISTEN:$SSH_AUTH_SOCK,fork EXEC:"npiperelay.exe -ei -s //./pipe/openssh-ssh-agent",nofork &) >/dev/null 2>&1
fi
