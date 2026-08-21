#!/usr/bin/env bash
# Pokrece dual-arm color-sorting demo (2x CRX-10iA + kamere + klasifikatori +
# sort_cell orkestrator, ros_plc_sim) u tmux sessioni.
#
# Cisto ROS2 -- NEMA PLC-a u petlji (sort_cell.py sam donosi sve odluke).
# Vidi ros_plc_sim/scripts/sort_cell.py i modbus_sensor_bridge.md/bridge_node.md
# za kako bi se PLC mogao ukljuciti kasnije.
#
# Koristi:
#   ./start_dual_arm_sort.sh              # pokreni
#   tmux attach -t dual_arm_sort          # zakaci se ako je vec pokrenuto
#   Ctrl+b pa d                           # detach (ostaje pokrenuto u pozadini)
#   tmux kill-session -t dual_arm_sort    # ugasi
set -e

SESSION="dual_arm_sort"
ROS_SETUP="source /opt/ros/jazzy/setup.bash && source /root/arms_ws/install/setup.bash"

if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Session '$SESSION' vec postoji. 'tmux attach -t $SESSION' da se zakacis, ili 'tmux kill-session -t $SESSION' da ugasis pa pokreni ponovo."
    exit 1
fi

tmux new-session -d -s "$SESSION" -n gazebo
tmux send-keys -t "$SESSION:gazebo" \
    "$ROS_SETUP && DISPLAY=:0 ros2 launch ros_plc_sim dual_arm_sort.launch.py" C-m

echo "Pokrenuto. 'tmux attach -t $SESSION' za gledanje logova."
echo "Sve (gazebo, move_group, kamere/klasifikatori, sort_cell orkestrator) je u JEDNOM launchu/prozoru."
echo "sort_cell sam spawn-a dijelove i sortira ih -- nema rucnog triggera, samo gledaj."
