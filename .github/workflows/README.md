# Bachata-S4 shadp2p (Android ARM64)

Experimental **Bachata-S4 + shadp2p/shadNet** build for running Bloodborne online features on Android ARM64.

This repository contains the GitHub Actions build workflow that combines the Bachata-S4 Android ARM64 base with the networking/shadNet pieces from the `Wozzardman/shadp2p` fork.

## Current Android status

Tested on Bloodborne **CUSA03173 / v1.09**.

Working in the current known-good build:

- shadNet connection and login
- Bloodborne server-information download
- Bloodborne online login
- shadNet WebAPI
- STUN / Matching2 startup
- Bloodborne community HTTP features
- asynchronous online presence such as other-player phantoms

Known limitation:

- **Traditional co-op summon is not confirmed working on Android yet.**
- The summon broker can advertise/search players, but the final Android peer/co-op connection still needs more ARM64/FEX work.
- Do not assume every upstream shadp2p PC feature is supported by this Android build.

## Important

This is experimental software.

- Back up your Bloodborne saves.
- Every player needs a **unique shadNet account**.
- Keep the Android client and the shadNet server on the same **Tailscale tailnet**.
- The Android build currently needs an IPv4 workaround for `thehuntersdream.com`.
- The public IPv4 address can change. See the online setup guide before copying an old address.

## Online setup

See **[ONLINE_SETUP.md](ONLINE_SETUP.md)** for the full Android + shadNet + Tailscale tutorial.

Quick summary:

1. Run a compatible `shadnet-p2p` server.
2. Join the Android device and server to the same Tailscale tailnet.
3. Create a unique shadNet account for the Android player.
4. Install the Bachata-S4 shadp2p APK.
5. Configure:
   - Network connected = enabled
   - shadNet = enabled
   - Server = `<SERVER_TAILSCALE_IP>:31313`
   - WebAPI = `http://<SERVER_TAILSCALE_IP>:31315`
   - Signaling Info = blank
   - UPnP = disabled when using Tailscale
6. Put `users.json` and `host_overrides.json` in the Android shadPS4 runtime user-data folder.
7. Keep Tailscale connected and start Bloodborne in Online mode.

## Android shadPS4 user-data path

For this Bachata-S4 package, the runtime shadPS4 directory used by the emulator is:

```text
/data/user/0/com.bachatas4.android/files/runtime-home/.local/share/shadPS4/
```

Relative to `run-as com.bachatas4.android`:

```text
files/runtime-home/.local/share/shadPS4/
```

This is the directory that must contain:

```text
config.json
users.json
host_overrides.json
```

Do **not** use:

```text
/data/user/0/com.bachatas4.android/.local/share/shadPS4/
```

That is not the runtime configuration directory used by this build.

## Build workflow

The GitHub Actions workflow builds the ARM64 shadPS4 core and packages it into the Bachata-S4 APK runtime.

The build is pinned to specific upstream revisions so a rebuild does not silently pull unrelated upstream changes.

## Upstream projects

This work depends on:

- shadPS4
- Bachata-S4
- Wozzardman/shadp2p
- Wozzardman/shadnet-p2p / shadNet
- Tailscale for the private peer network

The upstream projects remain under their own licenses and ownership.

## Disclaimer

This project does not provide Bloodborne game files, PlayStation firmware files, copyrighted game assets, or Sony services.

Use a legally obtained game dump and the system files required by shadPS4.

This is an unofficial community project and is not affiliated with Sony Interactive Entertainment or FromSoftware.
