# syntax=docker/dockerfile:1.7
#
# Reproduces the full arms_ws ROS 2 Jazzy / Gazebo Harmonic workspace used
# for the FANUC R-2000iC/125L rail-cell (+ CRX-10iA, UR, PLC bridge, etc.)
# development. Build with BuildKit (needed for --mount=type=ssh):
#
#   DOCKER_BUILDKIT=1 docker build --ssh default -t arms_ws:latest .
#
# --ssh default forwards your local ssh-agent into the build so the one
# private source repo (ros_gui_bridge) can be cloned; make sure the right
# key is loaded first (ssh-add -l). All other repos are public and are
# cloned over plain HTTPS.

FROM ros:jazzy-ros-base

ENV DEBIAN_FRONTEND=noninteractive \
    ROS_DISTRO=jazzy \
    LANG=en_US.UTF-8

# ---------------------------------------------------------------------------
# System / ROS / Gazebo Harmonic / MoveIt packages
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        ros-jazzy-desktop \
        ros-jazzy-ros-gz \
        ros-jazzy-ros-gz-bridge \
        ros-jazzy-ros-gz-sim \
        ros-jazzy-ros-gz-interfaces \
        ros-jazzy-moveit \
        ros-jazzy-pilz-industrial-motion-planner \
        ros-jazzy-ros2-control \
        ros-jazzy-ros2-controllers \
        ros-jazzy-gz-ros2-control \
        ros-jazzy-rqt-joint-trajectory-controller \
        ros-jazzy-xacro \
        python3-numpy \
        python3-tk \
        python3-pip \
        python3-colcon-common-extensions \
        python3-rosdep \
        xterm \
        git \
        openssh-client \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir --break-system-packages asyncua pymodbus

RUN rosdep init || true && rosdep update

# ---------------------------------------------------------------------------
# Workspace source: clone every package at its pinned branch.
# ---------------------------------------------------------------------------

# plc_bridge lives inside a separate repo (plc-ros2-bridge) on the real
# machine and is symlinked into arms_ws/src -- reproduce that layout.
RUN mkdir -p /root/ros2_ws/src
WORKDIR /root/ros2_ws/src
RUN git clone --depth 1 -b crx-cell-integration \
    https://github.com/bb53192/plc-ros2-bridge.git plc-ros2-bridge

RUN mkdir -p /root/arms_ws/src
WORKDIR /root/arms_ws/src

# Public repos over HTTPS.
RUN git clone --depth 1 -b jazzy               https://github.com/UniversalRobots/Universal_Robots_ROS2_Description.git Universal_Robots_ROS2_Description && \
    git clone --depth 1 -b multiple_ur_robots  https://github.com/CroboticSolutions/Universal_Robots_ROS2_Driver.git Universal_Robots_ROS2_Driver && \
    git clone --depth 1 -b multiple_ur_robots  https://github.com/CroboticSolutions/Universal_Robots_ROS2_GZ_Simulation.git Universal_Robots_ROS2_GZ_Simulation && \
    git clone --depth 1 -b crx-integration     https://github.com/CroboticSolutions/arm_api2.git arm_api2 && \
    git clone --depth 1 -b apirsic/devel       https://github.com/CroboticSolutions/arm_api2_msgs.git arm_api2_msgs && \
    git clone --depth 1 -b main                https://github.com/CroboticSolutions/fanuc_description.git fanuc_description && \
    git clone --depth 1 -b main                https://github.com/CroboticSolutions/fanuc_driver.git fanuc_driver && \
    git clone --depth 1 -b r2000-gazebo        https://github.com/CroboticSolutions/fanuc_gazebo.git fanuc_gazebo && \
    git clone --depth 1 -b hmi-live-controls   https://github.com/bb53192/idustrial_demo_gui idustrial_demo_gui && \
    git clone --depth 1 -b multiple_ur_robots  https://github.com/CroboticSolutions/ros2_robotiq_gripper.git ros2_robotiq_gripper && \
    git clone --depth 1 -b pick-on-the-fly     https://github.com/bb53192/ros_plc_sim.git ros_plc_sim && \
    git clone --depth 1 -b ros2                https://github.com/tylerjw/serial.git serial

# Private repo: needs the forwarded ssh-agent (see --ssh default above).
RUN mkdir -p -m 0700 /root/.ssh && ssh-keyscan github.com >> /root/.ssh/known_hosts
RUN --mount=type=ssh git clone --depth 1 -b ros2 \
    git@github.com:CroboticSolutions/ros_gui_bridge.git ros_gui_bridge

RUN ln -s /root/ros2_ws/src/plc-ros2-bridge/arms_ws/src/plc_bridge /root/arms_ws/src/plc_bridge

# ---------------------------------------------------------------------------
# rosdep + build
# ---------------------------------------------------------------------------
WORKDIR /root/arms_ws
RUN . /opt/ros/jazzy/setup.sh && \
    rosdep install --from-paths src --ignore-src -r -y

RUN . /opt/ros/jazzy/setup.sh && \
    colcon build --symlink-install

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
