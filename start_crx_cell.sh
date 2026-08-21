#!/usr/bin/env bash
# Pokrece CRX gripper-cell (traka + CRX-10iA + Robotiq, ros_plc_sim) u tmux
# sessioni s odvojenim prozorima -- redoslijed prema RUNBOOK.md #6.
#
# Koristi:
#   ./start_crx_cell.sh                 # pokreni
#   tmux attach -t crx_cell             # zakaci se ako je vec pokrenuto
#   Ctrl+b pa 0-4                       # prebacivanje izmedju prozora
#   Ctrl+b pa d                         # detach (ostaje pokrenuto u pozadini)
#   tmux kill-session -t crx_cell       # ugasi sve odjednom
#
# OPCUA_URL MORA pokazivati na stroj gdje OpenPLC Runtime stvarno radi
# (tvoj laptop, ne ovaj sandbox) -- promijeni ako se IP promijenio.
#
# NAPOMENA: FB_CellCycle/FB_CellManual (stara PLC logika za ovu celiju) je
# obrisana iz program.st ranije u sesiji -- AUTO mode nece raditi dok se ne
# vrati. Default ovdje (start_mode=manual, manual_source=ros) zaobilazi PLC
# potpuno pa radi bez obzira na to -- HMI Overview belt/robot dugmad rade.
set -e

SESSION="crx_cell"
OPCUA_URL="${OPCUA_URL:-opc.tcp://127.0.0.1:4840/openplc/opcua}"
OPCUA_USER="${OPCUA_USER:-user}"
OPCUA_PASS="${OPCUA_PASS:-1234}"

ROS_SETUP="source /opt/ros/jazzy/setup.bash && source /root/arms_ws/install/setup.bash"

if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Session '$SESSION' vec postoji. 'tmux attach -t $SESSION' da se zakacis, ili 'tmux kill-session -t $SESSION' da ugasis pa pokreni ponovo."
    exit 1
fi

tmux new-session -d -s "$SESSION" -n bridge
tmux send-keys -t "$SESSION:bridge" \
    "$ROS_SETUP && OPCUA_URL=$OPCUA_URL OPCUA_USER=$OPCUA_USER OPCUA_PASS=$OPCUA_PASS ros2 run plc_bridge bridge_node" C-m

tmux new-window -t "$SESSION" -n modbus
tmux send-keys -t "$SESSION:modbus" \
    "$ROS_SETUP && ros2 run plc_bridge modbus_sensor_bridge" C-m

tmux new-window -t "$SESSION" -n gazebo
tmux send-keys -t "$SESSION:gazebo" \
    "$ROS_SETUP && DISPLAY=:0 ros2 launch ros_plc_sim crx_gripper_plc.launch.py" C-m

tmux new-window -t "$SESSION" -n gui_bridge
tmux send-keys -t "$SESSION:gui_bridge" \
    "$ROS_SETUP && sleep 10 && ros2 launch ros_gui_bridge bridge.launch.py ip:=0.0.0.0" C-m

tmux new-window -t "$SESSION" -n gui_dev
tmux send-keys -t "$SESSION:gui_dev" \
    "cd /root/arms_ws/src/idustrial_demo_gui && export PATH=\"\$HOME/.bun/bin:\$PATH\" && bun run dev" C-m

tmux select-window -t "$SESSION:gazebo"

echo "Pokrenuto. 'tmux attach -t $SESSION' za gledanje logova (Ctrl+b pa 0-4 za prozore)."
echo "Prozori: 0=bridge  1=modbus  2=gazebo  3=gui_bridge  4=gui_dev"
echo "gui_bridge ceka 10s da se ros_gui_bridge port oslobodi/gazebo digne."
echo "Otvori http://localhost:<port ispisan u gui_dev prozoru>/hmi kad je gui_dev spreman."
