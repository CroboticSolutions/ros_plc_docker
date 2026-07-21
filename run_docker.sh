#!/bin/bash
# Mirrors CroboticSolutions/docker_files' run_docker.sh (the script this
# dev container was originally started with) so X11/SSH-agent forwarding
# behave the same way. --gpus all is dropped: that flag is NVIDIA-Container-
# Toolkit-specific and fails outright ("no known GPU vendor found") on
# machines without an NVIDIA GPU/runtime -- integrated graphics (AMD/Intel)
# just work via Mesa/X11 through the /dev:/dev mount below, no --gpus needed.
# If you do have an NVIDIA GPU + nvidia-container-toolkit installed, add
# --gpus all back in.

CONTAINER_NAME=arms_ws_cont
IMAGE_NAME=arms_ws:latest

# Hook to the current SSH_AUTH_SOCK, since it changes across logins:
# https://www.talkingquickly.co.uk/2021/01/tmux-ssh-agent-forwarding-vs-code/
ln -sf "$SSH_AUTH_SOCK" ~/.ssh/ssh_auth_sock

docker run \
  -it \
  --network host \
  --privileged \
  --volume /dev:/dev \
  --volume /tmp/.X11-unix:/tmp/.X11-unix \
  --volume ~/.ssh/ssh_auth_sock:/ssh-agent \
  --env SSH_AUTH_SOCK=/ssh-agent \
  --env DISPLAY="$DISPLAY" \
  --env TERM=xterm-256color \
  --name "$CONTAINER_NAME" \
  "$IMAGE_NAME" \
  /bin/bash
