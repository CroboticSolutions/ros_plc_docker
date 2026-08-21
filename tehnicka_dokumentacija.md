# Tehnička dokumentacija — detaljna referenca

Prateći dokument uz `prezentacija_sadrzaj.md`. Ovo je "duboka" verzija — za nekoga tko želi točno znati gdje što piše, koji port, koji fajl, koja poznata ograničenja postoje. Sažetak istraživanja provedenog kroz repo na dan 2026-08-17.

---

## 1. Arhitektura / tok podataka

```
OpenPLC Runtime (Docker, ghcr.io/autonomy-logic/openplc-runtime, v4)
   |  OPC UA :4840  (opc.tcp://<host>:4840/openplc/opcua)
   |  Modbus TCP :502  (master, poll prema plc_bridge senzor serveru)
   v
plc_bridge (ROS2 paket u plc-ros2-bridge repou)
   - bridge_node.py     -> OPC UA klijent, prevodi u /plc/<var> i /plc/write/<var> ROS topice
   - modbus_sensor_bridge.py -> Modbus TCP server (senzor mock), sluša na :502
   v
ROS2 topici (/plc/*, /plc/write/*, /sensors/*)
   v
ROS2 + Gazebo simulacija (cell_io.py, cell_mode.py, tending_node.py, door_bridge_node.py, itd.)
   v
ros_gui_bridge (WebSocket server, :9093, /ros endpoint)
   v
idustrial_demo_gui (React/Vite HMI, dev server :8080, spaja se na ws://<host>:9093/ros)
```

---

## 2. Repozitoriji (stanje na dan istraživanja)

| Repo | Remote | Branch | Napomena |
|---|---|---|---|
| `fanuc_gazebo` | github.com/bb53192/fanuc_gazebo | `opw-kinematics` | čist, puna povijest (12 commitova) |
| `ros_plc_sim` | github.com/bb53192/ros_plc_sim | `pick-on-the-fly` | čist, shallow clone (1 commit lokalno) |
| `ros_gui_bridge` | github.com:CroboticSolutions/ros_gui_bridge | `ros2` | čist, shallow clone |
| `idustrial_demo_gui` | github.com/bb53192/idustrial_demo_gui | `hmi-live-controls` | čist, shallow clone, Lovable-connected |
| `arm_api2` | github.com:bb53192/arm_api2 | `crx-integration` | čist, puna povijest (224 commita) |
| `arm_api2_msgs` | github.com/CroboticSolutions/arm_api2_msgs | `apirsic/devel` | čist, puna povijest (22 commita) |
| `plc-ros2-bridge` | github.com/bb53192/plc-ros2-bridge | `crx-cell-integration` | **ima lokalne necommitane izmjene** (program.st, exports/) |

`plc_bridge` (u `arms_ws/src/`) je samo symlink na `plc-ros2-bridge/arms_ws/src/plc_bridge` — nije zaseban git repo, dio je `plc-ros2-bridge` povijesti.

Shallow clone repoi (`ros_plc_sim`, `ros_gui_bridge`, `idustrial_demo_gui`, `plc-ros2-bridge`) pokazuju samo zadnji commit lokalno — treba `git fetch --unshallow` ako je puna povijest ikad potrebna.

---

## 3. Portovi i servisi — puna tablica

| Servis | Port | Protokol | Gdje je definiran | Pokreće se s |
|---|---|---|---|---|
| ros_gui_bridge WebSocket | 9093 | WebSocket | hardkodirano `WEBSOCKET_PORT = 9093` u `ros_gui_bridge/ros_gui_bridge/bridge.py:39` | `ros2 launch ros_gui_bridge bridge.launch.py` |
| idustrial_demo_gui dev server | 8080 | HTTP | nije u repou eksplicitno (Lovable vite config auto-detect); dokumentirano u `ros_plc_sim/RUNBOOK.md:30,132` | `bun run dev` |
| HMI → bridge WebSocket klijent | 9093 (`/ros`) | WebSocket client | `VITE_BRIDGE_URL` env override, fallback hardkodiran u 3 hook fajla (`use-bridge.tsx`, `use-robot-state.ts`, `use-hmi-variables.ts`) | pokreće se s dev serverom |
| plc_bridge bridge_node.py (OPC UA klijent) | 4840 | OPC UA | `OPCUA_URL` env var, default `opc.tcp://127.0.0.1:4840/openplc/opcua` (`bridge_node.py:13`) | `ros2 run plc_bridge bridge_node` |
| plc_bridge modbus_sensor_bridge.py | 502 | Modbus TCP (server) | `MODBUS_HOST="0.0.0.0"`, `MODBUS_PORT=502` (`modbus_sensor_bridge.py:17-18`) | `ros2 run plc_bridge modbus_sensor_bridge` |
| OpenPLC OPC UA server | 4840 | OPC UA | `opcua.json:11` — `opc.tcp://0.0.0.0:4840/openplc/opcua` | dio OpenPLC runtime kontejnera |
| OpenPLC Modbus master | 502 (prema `192.168.248.129`) | Modbus TCP (client) | `modbus_master.json:8-9` | dio OpenPLC runtime kontejnera |
| OpenPLC modbus_slave plugin | 502 | Modbus TCP | **namjerno isključen** (`plugins.conf`, flag 0) da ne blokira port koji koristi `modbus_sensor_bridge.py` | — |
| OpenPLC web UI | — | HTTPS | **nije dokumentirano u repou**; potvrđeno u praksi: `8443` (ne 8080!) | Docker kontejner, `--network host` |

**ROS_DOMAIN_ID**: dokumentiran samo u `ros_plc_sim/RUNBOOK.md` (`export ROS_DOMAIN_ID=10`), za pick&place i dual-arm-sort demo. **Nije dokumentiran nigdje za CNC/rail cell (`fanuc_gazebo`)** — gap koji vrijedi popuniti ako se oba demoa ikad voze paralelno.

---

## 4. OpenPLC — verzija i porijeklo

- Slika: `ghcr.io/autonomy-logic/openplc-runtime` (upstream AutonomyLogic), **verzija/tag nije pinan nigdje u repou** — samo generički "v4" u proznom tekstu README-a.
- CroboticSolutions se spominje samo kao izvor ROS2/`arm_api2_tutorial` Docker kontejnera (`CroboticSolutions/docker_files`) — **nije** izvor OpenPLC forka. OpenPLC je čisti upstream, ne CroboticSolutions fork.
- Preporuka: ako je bitno za reproducibilnost, snimi točan image tag/digest iz lokalnog `docker images`/`docker inspect` i zapiši u README (trenutno nedostaje).

---

## 5. plc_bridge — kako radi (bridge_node.py)

- **OPC UA varijable se otkrivaju live browsanjem servera** (`discover_variables()`, `bridge_node.py:40-66`) — `opcua.json` se NE čita direktno od strane bridge_node-a (to je samo config za OpenPLC-ov OPC UA server plugin).
- Otkrivanje se radi **JEDNOM po pokretanju procesa**, odmah nakon spajanja (`opcua_loop()`, linije 136-139). Nema live re-discovery, nema file-watchinga, nema periodičkog re-browsanja.
- **Posljedica: nakon svake promjene u OpenPLC programu koja mijenja izložene OPC UA varijable (novi var, obrisan var, promijenjen tip), `bridge_node` proces se MORA restartati** da bi pokupio promjene. Ovo je najvažnija operativna činjenica za bilo koji runbook.
- Read/write konvencija: svaka varijabla dobiva publisher na `/plc/<var>` (svaki poll ciklus, 100ms, namjerno i bez promjene — kasni subscriberi uvijek dobiju trenutno stanje). Ako je varijabla writable u OPC UA (permission "rw"), dodatno dobiva subscriber na `/plc/write/<var>` koji queue-a upis, izvršen sljedeći poll ciklus.
- Nema reconnect/retry logike — ako OPC UA konekcija padne (npr. OpenPLC restart), `bridge_node` proces baca exception i treba ga ručno restartati.
- Env varijable: `OPCUA_URL`, `OPCUA_USER` (default "admin"), `OPCUA_PASS` (default "1234"). Prazan `OPCUA_USER` = anonymous login.
- **Poznati bug u dokumentaciji**: `plc-ros2-bridge/README.md` kaže da `bridge_node.py` čita `OPCUA_HOST` — kod zapravo čita `OPCUA_URL`. Treba ispraviti README.

## 6. plc_bridge — modbus_sensor_bridge.py

- Standalone Modbus TCP server (ne klijent) koji ogledava 3 ROS bool topica (`/sensors/motion`, `/sensors/door_closed`, `/sensors/part_present`) u Modbus discrete-input registre, da ih OpenPLC-ov Modbus master može pollati kao slave uređaj.
- Nema discovery koraka, nema ovisnosti o OpenPLC adresnom prostoru — treba restart samo ako se mijenja sam kod (npr. dodaje 4. senzor) ili port/host.

---

## 7. Postojeća dokumentacija (već napisana, za referencu)

- `ros_plc_sim/RUNBOOK.md` — arhitektura, build/run koraci, poznati TODO-i, dual-arm-sort demo
- `ros_plc_sim/docs/CHECKPOINT.md` (hrvatski) — duboka narativna dokumentacija PoC-a, Modbus vs OPC UA rationale
- `fanuc_gazebo/README.md` — **zastario**, ne odražava rail-cell/CNC-tending rad vidljiv u git logu te grane
- `ros_gui_bridge/README.md` — **zastario**, još opisuje ROS1/catkin iako je kod portan na ROS2 rclpy

## 8. Poznati gapovi

- CNC/rail ćelija (`fanuc_gazebo`) nema svoj RUNBOOK ni dokumentiran `ROS_DOMAIN_ID`
- `idustrial_demo_gui` (web HMI) trenutno nema NIKAKVU vezu s CNC ćelijom — prikazuje samo staru pick&place ćeliju
- `plc-ros2-bridge` ima necommitane lokalne izmjene (CNC1/CNC2 PLC program) — treba commit+push kad korisnik odluči
