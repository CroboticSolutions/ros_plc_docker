#!/usr/bin/env bash
# Pokrece cijeli CNC tending stack u tmux sessioni s odvojenim prozorima,
# jedan po servisu (isti obrazac kao RUNBOOK.md "each in its own terminal").
#
# Koristi:
#   ./start_cnc_tending.sh              # pokreni
#   tmux attach -t cnc_tending          # zakaci se ako je vec pokrenuto
#   Ctrl+b pa 0-4                        # prebacivanje izmedju prozora
#   Ctrl+b pa d                         # detach (ostaje pokrenuto u pozadini)
#   tmux kill-session -t cnc_tending    # ugasi sve odjednom
#
# OPCUA_URL MORA pokazivati na stroj gdje OpenPLC Runtime stvarno radi
# (tvoj laptop, ne ovaj sandbox) -- promijeni ako se IP promijenio.
set -e

SESSION="cnc_tending"
OPCUA_URL="${OPCUA_URL:-opc.tcp://127.0.0.1:4840/openplc/opcua}"
OPCUA_USER="${OPCUA_USER:-engineer}"
OPCUA_PASS="${OPCUA_PASS:-1234}"

ROS_SETUP="source /opt/ros/jazzy/setup.bash && source /root/arms_ws/install/setup.bash"

if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Session '$SESSION' vec postoji. 'tmux attach -t $SESSION' da se zakacis, ili 'tmux kill-session -t $SESSION' da ugasis pa pokreni ponovo."
    exit 1
fi

tmux new-session -d -s "$SESSION" -n bridge
tmux send-keys -t "$SESSION:bridge" \
    "$ROS_SETUP && OPCUA_URL=$OPCUA_URL OPCUA_USER=$OPCUA_USER OPCUA_PASS=$OPCUA_PASS ros2 run plc_bridge bridge_node" C-m

tmux new-window -t "$SESSION" -n gazebo
tmux send-keys -t "$SESSION:gazebo" \
    "$ROS_SETUP && DISPLAY=:0 ros2 launch fanuc_gazebo r2000_gz_sim_moveit.launch.py gazebo_gui:=true launch_rviz:=false launch_move_group:=true" C-m

tmux new-window -t "$SESSION" -n arm_api2
tmux send-keys -t "$SESSION:arm_api2" \
    "$ROS_SETUP && sleep 15 && ros2 launch arm_api2 moveit2_simple_iface.launch.py robot_name:=r2000 use_sim_time:=true launch_joy:=false" C-m

tmux new-window -t "$SESSION" -n door_bridge
tmux send-keys -t "$SESSION:door_bridge" \
    "$ROS_SETUP && sleep 20 && ros2 run fanuc_gazebo door_bridge_node.py" C-m

tmux new-window -t "$SESSION" -n tending
tmux send-keys -t "$SESSION:tending" \
    "$ROS_SETUP && sleep 25 && ros2 run fanuc_gazebo tending_node.py" C-m

tmux new-window -t "$SESSION" -n gui_bridge
tmux send-keys -t "$SESSION:gui_bridge" \
    "$ROS_SETUP && sleep 10 && ros2 launch ros_gui_bridge bridge.launch.py ip:=0.0.0.0" C-m

tmux select-window -t "$SESSION:gazebo"

echo "Pokrenuto. 'tmux attach -t $SESSION' za gledanje logova (Ctrl+b pa 0-5 za prozore)."
echo "Prozori: 0=bridge  1=gazebo  2=arm_api2  3=door_bridge  4=tending  5=gui_bridge"
echo "arm_api2/door_bridge/tending cekaju 15/20/25s da se gazebo/move_group podigne prije pokretanja."
echo "arm_api2 (moveit2_simple_iface) je OBAVEZAN -- tending_node's _cart_mode()/_lin() pozivi"
echo "(arm/change_state, arm/move_to_pose) inace vise/timeoutaju bez ikakvog jasnog razloga u logu."
echo "gui_bridge sluzi WebSocket na :9093 za idustrial_demo_gui HMI, bind na 0.0.0.0 (LAN pristup)."
