#!/bin/bash
# Mirrors CroboticSolutions/docker_files' run_docker.sh (the script this
# dev container was originally started with) so GPU/X11/SSH-agent
# forwarding behave the same way.

CONTAINER_NAME=arms_ws_cont
IMAGE_NAME=arms_ws:latest

# Hook to the current SSH_AUTH_SOCK, since it changes across logins:
# https://www.talkingquickly.co.uk/2021/01/tmux-ssh-agent-forwarding-vs-code/
ln -sf "$SSH_AUTH_SOCK" ~/.ssh/ssh_auth_sock

docker run \
  -it \
  --network host \
  --privileged \
  --gpus all \
  --volume /dev:/dev \
  --volume /tmp/.X11-unix:/tmp/.X11-unix \
  --volume ~/.ssh/ssh_auth_sock:/ssh-agent \
  --env SSH_AUTH_SOCK=/ssh-agent \
  --env DISPLAY="$DISPLAY" \
  --env TERM=xterm-256color \
  --name "$CONTAINER_NAME" \
  "$IMAGE_NAME" \
  /bin/bash
