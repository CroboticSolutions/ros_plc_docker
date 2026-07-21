# arms_ws Docker image

Extends Crobotic's `arm_api2` tutorial base image
([CroboticSolutions/docker_files](https://github.com/CroboticSolutions/docker_files/tree/master/ros2/jazzy/arm_api2))
-- the exact image this dev container was originally built from -- with
every other package added to this workspace since: `fanuc_description`,
`fanuc_driver`, `fanuc_gazebo`, `ros2_robotiq_gripper`, the UR ROS 2
stack, `ros_plc_sim`, `idustrial_demo_gui`, `ros_gui_bridge`, `serial`,
and `plc_bridge` (nested inside `plc-ros2-bridge`).

All repos are cloned fresh from GitHub at build time, at the branch each
one is currently on. **Two repos are private**: `ros_gui_bridge`, and
`arm_api2` itself -- the `crx-integration` branch lives on `bb53192`'s
private fork, not the public `CroboticSolutions/arm_api2` upstream.
Everything else is public.

## Build

Requires Docker BuildKit (for SSH-agent forwarding into the build, needed
to clone the two private repos).

```bash
ssh-add -l                      # make sure a key with access to both private repos is loaded
DOCKER_BUILDKIT=1 docker build --ssh default -t arms_ws:latest .
```

## Run (with GUI)

`run_docker.sh` mirrors the original tutorial's `run_docker.sh`:
`--network host --privileged --gpus all`, `/dev` and the X11 socket
mounted, and your `SSH_AUTH_SOCK` forwarded in (so `git`/private-repo
access still works from inside the running container, not just at build
time).

```bash
xhost +local:docker             # allow the container to open windows on your X server
./run_docker.sh
```

ROS 2 + the workspace are sourced automatically via `.bashrc` (matching
how the original image does it), so things just work in any shell you
open in the container, e.g.:

```bash
ros2 launch fanuc_gazebo r2000_gz_sim_moveit.launch.py
```

## Notes

- Base: Ubuntu 24.04 (Noble) + ROS 2 Jazzy desktop-full + Gazebo Harmonic
  (via `ros-jazzy-ros-gz-*`) + MoveIt (Servo, Visual Tools, Pilz LIN/PTP/
  CIRC planner) + `ros2_control`/`gz_ros2_control` +
  `rqt_joint_trajectory_controller` (used for manually teaching joint
  waypoints) + `xterm` (keyboard servo teleop).
- `plc_bridge` is not its own top-level repo -- it lives inside
  `bb53192/plc-ros2-bridge` at `arms_ws/src/plc_bridge` and is symlinked
  into this workspace's `src/`, matching the layout on the original
  machine.
- `asyncua` (OPC UA) and `pymodbus` (Modbus) are installed via pip for
  the PLC bridge; everything else comes from `rosdep install`.
- `arm_api2` is pinned to `crx-integration` here (this workspace's
  current branch), not the tutorial image's original `apirsic/devel`.
- Uncommitted local-only changes that existed only in the working tree
  on the original machine (small tweaks in `Universal_Robots_ROS2_Driver`,
  `ros_plc_sim/scripts/color_classifier.py`, and
  `plc_bridge/plc_bridge/bridge_node.py`) are **not** captured here --
  only what was committed and pushed. Commit/push those first if you
  want them included.
- Each build re-clones everything at the pinned branch's current HEAD --
  there's no incremental/cached rebuild story here.
