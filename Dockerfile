######################################################################
# arms_ws: extends Crobotic's arm_api2 tutorial base image
# (CroboticSolutions/docker_files/ros2/jazzy/arm_api2/Dockerfile,
# the exact base this dev container itself was built from -- confirmed
# by matching RMW_IMPLEMENTATION/ROS2_DISTRO env + .bashrc) with the
# additional packages built up in this workspace since: fanuc_description,
# fanuc_driver, fanuc_gazebo, ros2_robotiq_gripper, the UR ROS2 stack,
# ros_plc_sim, idustrial_demo_gui, ros_gui_bridge, serial, and the
# plc_bridge (nested inside plc-ros2-bridge).
#
# Build (needs BuildKit, for --mount=type=ssh to clone the one private
# repo, ros_gui_bridge):
#
#   ssh-add -l                      # make sure a key with ros_gui_bridge access is loaded
#   DOCKER_BUILDKIT=1 docker build --ssh default -t arms_ws:latest .
######################################################################

FROM ubuntu:noble

ENV HOME=/root \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    ROS2_DISTRO=jazzy \
    ROS_DISTRO=jazzy \
    DEBIAN_FRONTEND=noninteractive \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=graphics,utility,compute \
    TZ=Europe/Zagreb \
    RCUTILS_CONSOLE_OUTPUT_FORMAT="[{severity}] [{time}] [{name}]: {message}"
ARG PY_VENV=${HOME}/py_global

RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone

# ---------------------------------------------------------------------------
# Base system + dev tools (same list as the arm_api2 tutorial image)
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -q -y \
    apt-utils build-essential bc cmake curl git gnupg lsb-release \
    libboost-dev sudo nano net-tools tmux tmuxinator wget ranger htop \
    libgl1 libegl1 libglu1-mesa mesa-utils x11-apps \
    python3-venv python3-pip python3-tk \
    librange-v3-dev libserial-dev

RUN python3 -m venv ${PY_VENV} --system-site-packages
ENV PATH="${PY_VENV}/bin:$PATH"

# ---------------------------------------------------------------------------
# ROS 2 Jazzy
# ---------------------------------------------------------------------------
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | tee /etc/apt/sources.list.d/ros2.list > /dev/null
RUN apt-get update

RUN apt-get install -y \
    ros-${ROS2_DISTRO}-desktop-full \
    ros-${ROS2_DISTRO}-test-msgs \
    ros-${ROS2_DISTRO}-generate-parameter-library

RUN apt-get install -y \
    python3-argcomplete ros-dev-tools python3-colcon-common-extensions \
    python3-colcon-mixin python3-vcstool \
    ros-jazzy-navigation2 ros-jazzy-nav2-bringup

RUN colcon mixin add default https://raw.githubusercontent.com/colcon/colcon-mixin-repository/master/index.yaml
RUN colcon mixin update default

RUN apt-get install -y \
    ros-${ROS2_DISTRO}-ackermann-msgs \
    ros-${ROS2_DISTRO}-backward-ros

# Gazebo (Harmonic, via ros-gz's own dependency pin -- this workspace
# needs it unconditionally, unlike the tutorial image where it's optional).
RUN apt-get install -y \
    ros-${ROS2_DISTRO}-ros-gz-sim \
    ros-${ROS2_DISTRO}-ros-gz-bridge \
    ros-${ROS2_DISTRO}-ros-gz-interfaces

RUN echo "" >> ~/.bashrc && \
    echo "source /opt/ros/${ROS2_DISTRO}/setup.bash" >> ~/.bashrc

RUN apt-get install -y ros-${ROS2_DISTRO}-rmw-cyclonedds-cpp
ENV RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
RUN echo "export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp" >> ~/.bashrc

# MoveIt Servo/Visual Tools (as in the tutorial image) + this project's
# additions: Pilz LIN/PTP/CIRC planner, ros2_control + gz_ros2_control,
# rqt_joint_trajectory_controller (manual joint teaching), xacro, xterm
# (keyboard servo teleop terminal).
RUN apt-get update && apt-get install -y \
    ros-jazzy-moveit-servo \
    ros-jazzy-moveit-visual-tools \
    ros-jazzy-pilz-industrial-motion-planner \
    ros-jazzy-ros2-control \
    ros-jazzy-ros2-controllers \
    ros-jazzy-gz-ros2-control \
    ros-jazzy-rqt-joint-trajectory-controller \
    ros-jazzy-xacro \
    xterm

RUN pip3 install empy catkin_pkg lark

# ---------------------------------------------------------------------------
# Workspace source
# ---------------------------------------------------------------------------
WORKDIR /root/ros2_ws/src
RUN git clone --depth 1 -b crx-cell-integration \
    https://github.com/bb53192/plc-ros2-bridge.git plc-ros2-bridge

WORKDIR /root/arms_ws/src

RUN git clone -b apirsic/devel https://github.com/CroboticSolutions/arm_api2_msgs.git

# arm_api2 itself is cloned from bb53192's fork (crx-integration branch,
# private) below, alongside ros_gui_bridge -- both need the ssh-agent.

RUN git clone --depth 1 -b jazzy               https://github.com/UniversalRobots/Universal_Robots_ROS2_Description.git && \
    git clone --depth 1 -b multiple_ur_robots  https://github.com/CroboticSolutions/Universal_Robots_ROS2_Driver.git && \
    git clone --depth 1 -b multiple_ur_robots  https://github.com/CroboticSolutions/Universal_Robots_ROS2_GZ_Simulation.git && \
    git clone --depth 1 -b main                https://github.com/CroboticSolutions/fanuc_description.git && \
    git clone --depth 1 --recurse-submodules -b main https://github.com/CroboticSolutions/fanuc_driver.git && \
    git clone --depth 1 -b r2000-gazebo        https://github.com/CroboticSolutions/fanuc_gazebo.git && \
    git clone --depth 1 -b hmi-live-controls   https://github.com/bb53192/idustrial_demo_gui && \
    git clone --depth 1 -b multiple_ur_robots  https://github.com/CroboticSolutions/ros2_robotiq_gripper.git && \
    git clone --depth 1 -b pick-on-the-fly     https://github.com/bb53192/ros_plc_sim.git && \
    git clone --depth 1 -b ros2                https://github.com/tylerjw/serial.git

# Private repos -- need the forwarded ssh-agent (--ssh default).
RUN mkdir -p -m 0700 /root/.ssh && ssh-keyscan github.com >> /root/.ssh/known_hosts
RUN --mount=type=ssh git clone -b crx-integration \
    git@github.com:bb53192/arm_api2.git
RUN --mount=type=ssh git clone --depth 1 -b ros2 \
    git@github.com:CroboticSolutions/ros_gui_bridge.git

# plc_bridge lives inside plc-ros2-bridge on the real machine and is
# symlinked into arms_ws/src rather than being its own top-level repo.
RUN ln -s /root/ros2_ws/src/plc-ros2-bridge/arms_ws/src/plc_bridge /root/arms_ws/src/plc_bridge

# ---------------------------------------------------------------------------
# rosdep + build
# ---------------------------------------------------------------------------
WORKDIR /root/arms_ws
RUN rosdep init
RUN rosdep update && \
    rosdep install --from-paths src --ignore-src -r -y

# PLC bridge's OPC UA / Modbus clients (not resolved by rosdep -- plain pip deps).
RUN pip3 install asyncua pymodbus

RUN /bin/bash -c "source /opt/ros/jazzy/setup.bash && \
    python3 -m colcon build --symlink-install"

RUN echo "source ${PY_VENV}/bin/activate" >> $HOME/.bashrc
RUN echo "source /root/arms_ws/install/setup.bash" >> ~/.bashrc

CMD ["bash"]
