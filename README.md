# arms_ws Docker image

Reproduces the full `arms_ws` ROS 2 Jazzy / Gazebo Harmonic workspace
(FANUC R-2000iC/125L rail cell, CRX-10iA, UR arms, Robotiq gripper,
`arm_api2`, PLC bridge, ...) so the dev container can be torn down and
rebuilt on demand.

All source repos are cloned fresh from GitHub at build time, at the exact
branch each one was on when this image was put together. **`ros_gui_bridge`
is the only private repo** in the set -- everything else is public.

## Build

Requires Docker BuildKit (for SSH-agent forwarding into the build, needed
to clone the private repo).

```bash
ssh-add -l                      # make sure a key with ros_gui_bridge access is loaded
DOCKER_BUILDKIT=1 docker build --ssh default -t arms_ws:latest .
```

Or with compose:

```bash
docker compose build
```

## Run (with GUI)

Gazebo/RViz windows are forwarded to the host via X11.

```bash
xhost +local:docker             # allow the container to open windows on your X server
docker compose run --rm arms_ws
```

Inside the container, ROS/the workspace are already sourced (see
`entrypoint.sh`). Launch things as usual, e.g.:

```bash
ros2 launch fanuc_gazebo r2000_gz_sim_moveit.launch.py
```

`network_mode: host` is used so ROS 2/DDS discovery and Gazebo Transport
work without extra config -- this only isolates the container's
filesystem/processes, not its network, so if you need to keep it off the
host's ROS graph use `ROS_DOMAIN_ID`/`ROS_LOCALHOST_ONLY` as usual.

## Notes

- The image is built from `ros:jazzy-ros-base` + `ros-jazzy-desktop`,
  `ros-jazzy-ros-gz` (Gazebo Harmonic), `ros-jazzy-moveit`, the Pilz
  industrial motion planner, `ros2_control`/`ros2_controllers`,
  `gz_ros2_control`, and `rqt_joint_trajectory_controller`.
- `plc_bridge` is not its own top-level repo -- it lives inside
  `bb53192/plc-ros2-bridge` at `arms_ws/src/plc_bridge` and is symlinked
  into this workspace's `src/`, matching the layout on the original
  machine (see `plc-bridge-duplicate-package` notes if you have them).
- `asyncua` (OPC UA) and `pymodbus` (Modbus) are installed via pip for
  the PLC bridge; everything else comes from `rosdep install`.
- Uncommitted local changes that existed only in the working tree on the
  original machine (small tweaks in `Universal_Robots_ROS2_Driver`,
  `ros_plc_sim/scripts/color_classifier.py`, and
  `plc_bridge/plc_bridge/bridge_node.py`) are **not** captured here --
  only what was committed and pushed. Commit/push those first if you want
  them included.
- To rebuild after pushing new commits, just re-run the build -- there's
  no cache-friendly incremental update; each build re-clones everything
  at the pinned branch's current HEAD.
