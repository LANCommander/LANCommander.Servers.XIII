---
sidebar_label: Docker
---

# XIII Docker Container

This Docker container runs an XIII dedicated server. It is built on the WINE image and runs the retail game's Unreal Engine 2 server, `UCC.exe server`. The container doesn't download the game, so you provide the files.

## Quick Start

```yaml
services:
  xiii:
    image: lancommander/xiii:latest
    container_name: xiii

    ports:
      - 7777:7777/udp
      - 7099:7099/udp
      - 8777:8777/udp

    volumes:
      - "/data/Servers/XIII/Deathmatch:/config"

    environment:
      XIII_SERVER_NAME: "My XIII Server"
      XIII_GAME_TYPE: "dm"
      XIII_MAP: "DM_Banque"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

Copy an XIII install with patch **1.4** (the GOG release; the folder with `System/UCC.exe` and `Maps/`) into `Server/` before the first start. You can instead set `XIII_ARCHIVE_URL` to a zip of that folder.

## How It Starts

1. `PostInitialization/10-InitializeWinePrefix.ps1` (from the WINE image) creates the Wine prefix in `/config/wineprefix`.
2. `PostInitialization/20-InstallXIII.ps1` checks for `Server/System/UCC.exe`. If it's missing and `XIII_ARCHIVE_URL` is set, the hook downloads and extracts the archive and remounts the overlay.
3. `PostInitialization/25-PatchEngine.ps1` writes a patched `System/Engine.dll` into `Overlay/` (see below).
4. `PostInitialization/30-ConfigureXIII.ps1` copies `System/XIII.ini` to `System/Server.ini` (`XIII_INI`) if it doesn't exist yet. It does this through `Merged/`, so the file lands in `Overlay/System/`. It then sets `[URL] Port` and removes the Ubi.com master server uplink server actor.
5. `START_EXE` (`/usr/local/bin/xiii-server`) runs, from `System/` under Wine, the same command as the game's `ServerLauncher.exe`:

   ```
   UCC.exe server DM_Banque.unr?GameIdx=0?MapName=Winslow_Bank?NP=8?FF=0?FR=20?TI=15?Game=XIIIMP.XIIIMPGameInfo?AdminPassword=?Password=?SN=XIII_Server?Mutator=?LAN -port=7777 ini=Server.ini log=server.log
   ```

A successful start ends with:

```
UdpServerQuery(crt): Port 7099 successfully bound.
### DM_Banque.XIIIMPGameInfo0 PostBeginPlay
End LoadMap: DM_Banque.unr?...
Game engine initialized
```

After that the server prints nothing until players join.

## Configuration Options

### Ports

- **7777/udp**: Game (`XIII_PORT`)
- **7099/udp**: Server query (`UdpServerQuery`). It stays 7099 whatever `XIII_PORT` is. Any `\<word>\` packet gets `Pong\queryid\...\final\` back.
- **8777/udp**: LAN beacon. The in-game LAN browser broadcasts `REPORTQUERY` here and the server answers `XIII <query port>`.

### Game Types

`XIII_GAME_TYPE` picks the game class and `GameIdx` the same way the launcher's *Game type* list does:

| Value | Mode | Class |
|-------|------|-------|
| `dm` | Deathmatch | `XIIIMP.XIIIMPGameInfo` |
| `tdm` | Team Deathmatch | `XIIIMP.XIIIMPTeamGameInfo` |
| `ctf` | Capture The Flag | `XIIIMP.XIIIMPCTFGameInfo` |
| `hunt` | The Hunt | `XIIIMP.XIIIMPDuckGameInfo` |
| `sabotage` | Sabotage | `XIIIMP.XIIIMPBombGame` |
| `powerup` | Power Up | `XIIIMP.XIIIMPGameInfo` + `XIIIMP.MarioMutator` |

The server logs the values it applied (`MaxPlayers`, `fFriendlyFireScale`, `MaxTime` in seconds, `WinningScore`).

### Environment Variables

See the [README](../README.md#environment-variables) for the full table.

### Server ini

`Overlay/System/Server.ini` holds engine settings (net speeds, server actors, packages). Game rules are not stored there; they come from the command line. Delete the file to regenerate it from `XIII.ini`.

### Engine.dll Patch

XIII's `Engine.dll` (patch 1.3/1.4, built 2004-10-27) ends `UGameEngine::Init` with `Client->Viewports(0)->Exec("ToggleFullscreen")` and a second viewport call, and doesn't check `Client`. A dedicated server has no client, so stock `UCC server` dies right after `Game engine initialized`:

```
General protection fault!
History: UGameEngine::Init <- UServerCommandlet::Main
```

The hook replaces the first 8 bytes of that block (RVA `0x79EA0`) with a jump to 25 bytes in the unused tail of `.text` (RVA `0x16CA50`). That code runs the original instructions when there is a client and jumps past both viewport calls (RVA `0x79ED0`) when there isn't. It also grows `.text`'s VirtualSize to cover them. It only patches the known file (sha256 `92839b5036c001b267f29654930facabdeaf3ae3ebb15ac531d5c3dd0757312c`, patched `3bc904e9…3bc710`) and skips anything else with a warning. The patched copy is only used by the server; clients keep their own `Engine.dll`. Set `XIII_PATCH_ENGINE=false` to turn it off.

### Hooks

| Hook | When |
|------|------|
| `PreInstallXIII` / `PostInstallXIII` | Around the game file check/download |
| `PreInitializeWinePrefix` / `PostInitializeWinePrefix` | Around Wine prefix creation (WINE image) |

Put `.ps1` scripts in `config/Scripts/Hooks/<HookName>/`.

## Troubleshooting

- **`General protection fault!` after `Game engine initialized`**: `Engine.dll` isn't patched. Check the log for the `25-PatchEngine` line; an `Unknown Engine.dll` warning means your install isn't the patch 1.4 build.
- **Server not in the LAN browser**: the browser finds servers by UDP broadcast to 8777, so the container needs its own LAN address (macvlan/ipvlan) or host networking. Joining by IP works through port mapping.
- **The admin password shows up in `docker logs`**: the game prints the map URL and `ACCESS SetAdminPassword '<password>'` itself. The `Starting:` line from `xiii-server` masks it.
- **`System/UCC.exe not found`**: `Server/` must contain the game folder itself (`Server/System/UCC.exe`), not a folder that contains it.
