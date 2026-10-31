# XIII Server (Docker)

This repository provides a Dockerized **XIII** dedicated server. XIII (Ubisoft, 2003) is an Unreal Engine 2 game with no Linux server, so the image runs the game's own `UCC.exe server` under Wine, with the same command line as the game's `ServerLauncher.exe`.
The image builds on [`lancommander/wine`](https://github.com/LANCommander/LANCommander.Servers.WINE). It supports file overlaying using OverlayFS.

---

## Features

- Runs the retail game's `UCC.exe server` (headless; no graphics or sound are initialized)
- Game type, map, limits, server name and passwords are environment variables
- Patches a copy of `Engine.dll` so `UCC server` doesn't crash on start (see [Engine.dll patch](#enginedll-patch))
- A separate server ini (`System/Server.ini`) is created from the game's `XIII.ini`, and the dead Ubi.com master server uplink is removed
- UCC's console log goes to `docker logs`
- Supports file overlaying using OverlayFS (no file copying required)

## Docker Compose Example

```yaml
services:
  xiii:
    image: lancommander/xiii:latest
    container_name: xiii

    ports:
      - "7777:7777/udp"
      - "7099:7099/udp"
      - "8777:8777/udp"

    volumes:
      - ./config:/config

    environment:
      XIII_SERVER_NAME: "My XIII Server"
      XIII_GAME_TYPE: "dm"
      XIII_MAP: "DM_Banque"
      XIII_MAX_PLAYERS: "8"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

The in-game LAN browser finds servers by broadcast. That needs the container on the LAN itself (macvlan/ipvlan, or `network_mode: host`); with port mapping, clients join by IP.

---

## Game Files

XIII is retail software with no public download. You must provide an install with **patch 1.4** (Opaquit's unofficial patch, which includes the official 1.01–1.3 patches). The GOG release ships it. Clients must use the same version.

- copy the game folder (the one containing `System/`, `Maps/`, `Textures/` ...) to `config/Server/`, **or**
- set `XIII_ARCHIVE_URL` to a zip of that folder, e.g. a LANCommander archive. It is downloaded and extracted on first start, if `Server/System/UCC.exe` doesn't exist yet.

`Video/` (cutscenes) isn't needed by the server and can be left out.

## Directory Layout (Host)

```text
.
└── config/
    ├── Server/            # XIII install (System/, Maps/, Textures/ ...)
    ├── Overlay/           # Your files, layered on top of Server/ (System/Server.ini, the patched
    │                      #   System/Engine.dll and System/server.log land here)
    ├── Merged/            # Overlayfs merged view (auto-created, the server runs here)
    ├── wineprefix/        # Wine prefix (auto-created)
    └── Scripts/
        └── Hooks/         # PowerShell scripts run at container lifecycle hooks
```

---

## Environment Variables

These are in addition to the [WINE image's variables](https://github.com/LANCommander/LANCommander.Servers.WINE#environment).
The game settings go on the UCC command line (map URL options) on every start.

| Variable | Description | Default |
|----------|-------------|---------|
| `XIII_GAME_TYPE` | `dm` (Deathmatch), `tdm` (Team Deathmatch), `ctf` (Capture The Flag), `hunt` (The Hunt), `sabotage` (Sabotage), `powerup` (Power Up: Deathmatch with `XIIIMP.MarioMutator`) | `dm` |
| `XIII_MAP` | Start map, without `.unr`. See [Maps](#maps) | `DM_Banque` |
| `XIII_MAP_NAME` | Readable map name sent as `MapName`. Looked up in `System/MapList.ini` when empty | |
| `XIII_SERVER_NAME` | Server name (`SN`). Spaces become `_`, like the game's launcher does | `XIII Server` |
| `XIII_MAX_PLAYERS` | Max players (`NP`) | `8` |
| `XIII_FRAG_LIMIT` | Points limit (`FR`), `0` for none | `20` |
| `XIII_TIME_LIMIT` | Time limit in minutes (`TI`), `0` for none | `15` |
| `XIII_FRIENDLY_FIRE` | `true` turns friendly fire on (`FF`) | `false` |
| `XIII_PASSWORD` | Join password | |
| `XIII_ADMIN_PASSWORD` | Admin password | |
| `XIII_MUTATORS` | Extra mutator classes, comma-separated | |
| `XIII_LAN` | `true` adds `?LAN` (LAN server, as the launcher's *Network: LAN*) | `true` |
| `XIII_PORT` | Game port (`-port=`, and `[URL] Port` in the server ini) | `7777` |
| `XIII_URL_OPTIONS` | Extra map URL options, appended as `?<options>` | |
| `XIII_INI` | Server ini in `System/`, created from `XIII.ini` if missing | `Server.ini` |
| `XIII_MASTER_SERVER_UPLINK` | `true` keeps the `MasterServerUplink` server actor (Ubi.com, offline) | `false` |
| `XIII_PATCH_ENGINE` | `false` skips the `Engine.dll` patch | `true` |
| `XIII_ARCHIVE_URL` | Zip of the game folder, used if `Server/System/UCC.exe` is missing | |
| `START_EXE` | Launcher | `/usr/local/bin/xiii-server` |
| `START_ARGS` | Appended to the UCC command line | |

### Maps

From `System/MapList.ini` (patch 1.4). Any map works with any game type, but the prefixes show what each is built for.

| Map | Name | Map | Name |
|-----|------|-----|------|
| `DM_Banque` | Winslow Bank | `CTF_Base` | USS-Patriot |
| `DM_Base_XBox` | Platform 02 | `CTF_Sanc` | XX |
| `DM_Base` | Platform 03 | `CTF_Snow` | Kellownee |
| `DM_Base2` | AFM-10 | `CTF_Toits` | New York |
| `DM_Hual1` | Emerald | `CTF_Temple` | Temple |
| `DM_Amos` | FBI | `SB_USA2` | Docks (Sabotage) |
| `DM_Pal` | Bristol Suites | `SB_Hual1a` | Choland (Sabotage) |
| `DM_Spads_XBox` | SPADS | `SB_Camp` | Camp (Sabotage) |
| `DM_Spads` | SPADS 2 | `DM_USA2_demo` | Docks |
| `DM_PRock` | Plain Rock | `DM_Hual04a` | Hualpar |
| `DM_Warehouse` | Warehouse 33 | `DM_PRock01a` | Asylum |
| `DM_USA01` | USA | `DM_SM01` | SS-419 |
| `DM_LostTemple` | Lost Temple | | |

See [Documentation/Docker.md](Documentation/Docker.md) for more detail.

---

## Engine.dll Patch

XIII's `Engine.dll` (the 2004-10-27 build in patch 1.3/1.4) ends `UGameEngine::Init` by calling `Client->Viewports(0)->Exec("ToggleFullscreen")` without checking for a client. A dedicated server has none, so `UCC server` crashes right after `Game engine initialized` with `General protection fault! History: UGameEngine::Init <- UServerCommandlet::Main`.

The `25-PatchEngine` hook writes a patched copy to `Overlay/System/Engine.dll` that skips those viewport calls when there is no client. It only patches the known file (sha256 `92839b50…312c`) and leaves `Server/` untouched. Clients don't need it.

---

## Building

The image is built `FROM lancommander/wine:latest` by default. To build against a local base image:

```bash
docker build --build-arg BASE_IMAGE=lancommander/wine:local -t lancommander/xiii:local .
```

---

## License

XIII and Wine are distributed under their respective licenses.
This repository contains only Docker build logic and helper scripts licensed under MIT.
