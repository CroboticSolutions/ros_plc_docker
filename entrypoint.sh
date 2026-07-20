#!/bin/bash
set -e
source /opt/ros/jazzy/setup.bash
source /root/arms_ws/install/setup.bash
exec "$@"
