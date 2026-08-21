# RUNBOOK — pokretanje simulacija u ovom Docker containeru

Tri gotove simulacije, svaka ima svoj `start_*.sh` skript u `/root/arms_ws/`. Svaki skript
pokreće sve potrebne procese u zasebnoj `tmux` sessioni, po jedan prozor po servisu.

Zajedničke tmux komande za sve tri:
```
tmux attach -t <ime_sessije>     # zakaci se, gledaj logove
Ctrl+b pa 0-9                    # prebacivanje izmedju prozora
Ctrl+b pa d                      # detach (ostaje pokrenuto u pozadini)
tmux kill-session -t <ime>       # ugasi sve odjednom
```

**Prije svakog pokretanja provjeri da ništa staro ne vrti u pozadini** (Gazebo zna satima
trošiti CPU/RAM neprimijećeno ako zaboraviš ugasiti sesiju):
```bash
tmux list-sessions
ps aux | grep -E "gz sim|move_group" | grep -v grep
```

---

## 0. Preduvjet: OpenPLC Runtime (VAN ovog containera!)

Sve tri simulacije imaju `bridge` prozor (`plc_bridge`) koji se spaja na OpenPLC Runtime
preko OPC UA (port 4840). **`docker` naredba ne postoji unutar ovog containera** — Runtime
mora biti pokrenut kao ZASEBAN, susjedni container **na hostu**, ne odavde. Ako ga ne
pokreneš prvo, `bridge` prozor svake simulacije pući će s `ConnectionRefusedError` (ostatak
simulacije i dalje radi normalno preko MANUAL/ROS puta — samo PLC/AUTO put ne radi).

Na hostu (ne u ovom containeru):
```bash
docker run -d \
  --name openplc-runtime \
  --network host \
  --cap-add=SYS_NICE \
  --cap-add=SYS_RESOURCE \
  -v openplc-runtime-data:/var/run/runtime \
  ghcr.io/autonomy-logic/openplc-runtime:latest
```

- `--network host` je bitan (ne `-p 8443:8443`) — bez toga OPC UA (4840) i Modbus (502)
  portovi nisu dostupni bridgevima
- Nakon pokretanja: `https://localhost:8443` — u ovom projektu se to koristi kao web UI
  (login `user`/`1234`) za konfiguraciju OPC UA/Modbus varijabli i upload PLC programa.
  (Napomena: službeni README najnovije verzije tvrdi da nema browser UI-ja u `latest` tagu
  nego se sve radi preko desktop OpenPLC Editor aplikacije preko REST API-ja — ako
  `https://localhost:8443` ne radi kao web UI, to je vjerojatno razlog; provjeri koju
  verziju/tag stvarno voziš.)
- PLC projekt koji se uploada je [CroboticSolutions/openplc](https://github.com/CroboticSolutions/openplc)
  (`PLC_project/` folder) — vidi taj repo za sadržaj/postavljanje
- Fork za buildanje vlastite verzije runtimea: [CroboticSolutions/openplc-runtime](https://github.com/CroboticSolutions/openplc-runtime)
  (trenutno identičan upstreamu, `Autonomy-Logic/openplc-runtime`, spreman za buduće izmjene)

---

## 1. CRX gripper-cell (traka + pick&place, PLC-vozeno) — `./start_crx_cell.sh`

Jedan CRX-10iA + Robotiq gripper, traka, PLC (OpenPLC) vozi AUTO/MANUAL logiku.

```bash
cd /root/arms_ws
./start_crx_cell.sh
```

Prozori: `0=bridge 1=modbus 2=gazebo 3=gui_bridge 4=gui_dev`

- **`bridge`** — OPC UA most (`plc_bridge`). Treba OpenPLC Runtime da radi VAN ovog containera
  (na hostu, `ghcr.io/autonomy-logic/openplc-runtime`, web UI port **8443 HTTPS**). Ako
  OpenPLC nije gore, ovaj prozor samo greška-loopa — sve OSTALO i dalje radi (MANUAL/ROS
  put ne treba PLC).
  - Default credentials u skripti su `OPCUA_USER=user OPCUA_PASS=1234` (`engineer` je
    ranije često failao s `BadUserAccessDenied` nakon izmjena u OpenPLC config panelu).
- **`gazebo`** — Gazebo GUI + MoveIt (`crx_gripper_plc.launch.py`).
- **`gui_bridge`** — WebSocket most na `:9093`, sluša na `0.0.0.0` (LAN pristup radi).
- **`gui_dev`** — web HMI (Vite dev server), port ispisan u prozoru (obično `:8080`). Otvori
  `http://localhost:8080/hmi` (ili LAN IP ako pristupaš s drugog uređaja).

**Mode gotcha:** cell_mode zna startati u AUTO — ako gumbi na "Robot"/Overview tabu ne rade,
provjeri je li mod MANUAL:
```bash
ros2 service call /cell/set_mode std_srvs/srv/SetBool "{data: false}"   # false = MANUAL
```

---

## 2. CNC tending (rail + 2 CNC stroja) — `./start_cnc_tending.sh`

FANUC R-2000iC/125L na tračnici, servisira 2 CNC stroja (utovar/istovar preko rack-ova).

```bash
cd /root/arms_ws
./start_cnc_tending.sh
```

Prozori: `0=bridge 1=gazebo 2=arm_api2 3=door_bridge 4=tending 5=gui_bridge`

- **`arm_api2`** (`moveit2_simple_iface`) — **OBAVEZAN**. Bez njega `tending_node.py`-ev
  `_cart_mode()`/`_lin()` (Cartesian pokreti) tiho vise i padaju s `"future timeout"` nakon
  ~20-80s, bez ijasnog razloga u logu. Ovo je najčešći uzrok "job se ne pokreće/puca" ovdje.
- **`door_bridge`/`tending`** — čekaju 20s/25s da se gazebo/move_group/arm_api2 podignu.
- Ručno okidanje joba (bez PLC-a, direktno preko ROS-a — korisno za test):
  ```bash
  ros2 topic pub -1 /cnc_1/door_cmd std_msgs/msg/Float64 "{data: 0.9}"   # otvori vrata
  ros2 topic pub -1 /plc/job_slot std_msgs/msg/Int32 "{data: 2}"         # ucitaj slot 2
  ```

**Napomena:** `tending_node.py`/`r2000_kinematics.yaml` imaju IK fix (KDL `manipulator` grupa
umjesto nedostupnog OPW `arm` plugina) koji je i dalje necommitan lokalno u `fanuc_gazebo` —
provjeri `git status` prije nego pretpostaviš da je stanje čisto s GitHuba.

---

## 3. Dual-arm sortiranje po boji — `./start_dual_arm_sort.sh`

2x CRX-10iA (plavi/zeleni), kamere + klasifikatori boje, `sort_cell.py` orkestrator.
**Čisto ROS2, nema PLC-a u petlji** — sve odluke (routing po boji, kad koji robot pokupi)
donosi sam orkestrator.

```bash
cd /root/arms_ws
./start_dual_arm_sort.sh
```

Jedan prozor, jedan launch (`dual_arm_sort.launch.py`) — sve je uključeno (gazebo, move_group,
kamere, klasifikatori, orkestrator). Nema ručnog triggera, sam spawn-a dijelove i sortira ih.

---

## Brzi troubleshooting

| Simptom | Uzrok | Fix |
|---|---|---|
| `BadUserAccessDenied` u `bridge` prozoru | krivi OPC UA credentials | `OPCUA_USER=user OPCUA_PASS=1234` |
| Gumbi na HMI-ju ne rade, mode ostaje nepoznat | `gui_bridge` sluša samo na `localhost` | provjeri da je pokrenut s `ip:=0.0.0.0` (svi skriptovi to već rade) |
| CNC job "future timeout" nakon ~20-80s | `arm_api2` nije pokrenut | pokreni `moveit2_simple_iface.launch.py` (vidi §2) |
| Robot ne reagira na `/manual/*` ili `/plc/*` iako je sve gore | cell_mode u AUTO umjesto MANUAL | `ros2 service call /cell/set_mode std_srvs/srv/SetBool "{data: false}"` |
| Računalo usporava bez razloga | zaboravljena tmux sesija od prije | `tmux list-sessions`, ugasi sve što ne koristiš |
