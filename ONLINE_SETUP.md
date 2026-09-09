# Android Online Setup — Bachata-S4 shadp2p

This guide explains how to configure the Android Bachata-S4 shadp2p build for Bloodborne online features.

The Android port differs from the normal PC shadp2p setup because the shadPS4 runtime is stored inside Bachata's private Android app directory.

> **Current limitation:** general online functionality works in the known-good Android build, but co-op summon is still experimental/not confirmed working on Android.

---

## 1. What you need

### Server side

One PC must run the compatible shadNet/shadnet-p2p server.

The server uses:

| Protocol | Port | Purpose |
|---|---:|---|
| TCP | `31313` | shadNet login / game protocol |
| UDP | `31314` | STUN / matchmaking |
| TCP | `31315` | WebAPI / Bloodborne summon broker |

The server should listen on:

```text
0.0.0.0
```

Do **not** give players `0.0.0.0` as the server address.

### Android side

You need:

- this Bachata-S4 shadp2p APK
- Bloodborne CUSA03173 v1.09 for the currently tested setup
- Tailscale
- Termux
- Shizuku + `rish` if you need to edit Bachata's private runtime files
- a unique shadNet NPID and password

---

## 2. Set up Tailscale

The shadNet server PC and every player must be members of the same Tailscale tailnet.

On the server PC:

```powershell
tailscale ip -4
```

Example result:

```text
100.101.102.103
```

That is the address players use.

On Windows you can confirm the phone is visible:

```powershell
tailscale status
```

Test the Android peer:

```powershell
tailscale ping <ANDROID_TAILSCALE_IP>
```

A successful `pong` proves Tailscale peer reachability.

No normal router port-forwarding should be needed for this Tailscale setup.

---

## 3. Create a unique shadNet account

Every active player needs a different NPID/account.

Do **not** use the same NPID on PC and Android at the same time.

On the server, configure a registration secret in `shadnet.cfg` if you want private registration:

```ini
RegistrationSecretKey=YOUR_PRIVATE_REGISTRATION_KEY
```

With the server running, build the bundled registration client from the shadNet/shadnet-p2p source:

```bash
cd clientsample
cmake -G Ninja -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
```

Register a player:

```bash
./build/shadnet-sample 127.0.0.1 31313 register AndroidHunter PLAYER_PASSWORD player@example.com YOUR_PRIVATE_REGISTRATION_KEY
```

NPIDs should be unique.

The **registration key is not the player's password**.

---

## 4. Prepare `users.json`

The Android build reads the selected shadPS4 user's shadNet credentials from `users.json`.

The safest method is to configure the same unique shadNet account in a compatible PC shadPS4/shadp2p launcher and copy the generated `users.json`.

Normal Windows shadPS4 user-data path:

```text
%APPDATA%\shadPS4\users.json
```

Copy that file to the Android phone, for example:

```text
/storage/emulated/0/Download/users.json
```

Do not publish your real `users.json` if it contains private account information.

---

## 5. Start Shizuku and enter `rish`

Open Shizuku and start it normally.

In Termux, enter the Shizuku shell using your installed `rish` script:

```sh
./rish
```

The prompt will change to the Android shell.

Confirm Bachata supports `run-as`:

```sh
run-as com.bachatas4.android id
```

If `run-as` says the package is not debuggable, this particular file-copy method cannot access the app-private directory. Use a debuggable build or another authorized method to access the app data.

---

## 6. Find the real Bachata shadPS4 runtime directory

Run:

```sh
run-as com.bachatas4.android sh -c \
'find . -type f -name config.json -print'
```

For this build, the correct file is:

```text
./files/runtime-home/.local/share/shadPS4/config.json
```

So the real runtime directory is:

```text
/data/user/0/com.bachatas4.android/files/runtime-home/.local/share/shadPS4/
```

Relative `run-as` path:

```text
files/runtime-home/.local/share/shadPS4
```

Check it:

```sh
run-as com.bachatas4.android sh -c \
'ls files/runtime-home/.local/share/shadPS4'
```

---

## 7. Copy `users.json` into Bachata

While still in `rish`:

```sh
cat /sdcard/Download/users.json \
| run-as com.bachatas4.android sh -c \
'cat > files/runtime-home/.local/share/shadPS4/users.json'
```

Verify:

```sh
run-as com.bachatas4.android sh -c \
'ls -l files/runtime-home/.local/share/shadPS4/users.json'
```

---

## 8. Configure shadPS4 networking

The needed values are:

| Setting | Value |
|---|---|
| Network connected | `true` |
| shadNet | `true` |
| Server | `<SERVER_TAILSCALE_IP>:31313` |
| WebAPI Server | `http://<SERVER_TAILSCALE_IP>:31315` |
| Signaling Info | blank |
| UPnP | `false` for Tailscale |

The build contains shadNet and WebAPI support in the ARM64 core.

If Bachata exposes these settings in the UI, use the UI.

If not, edit the existing `config.json` carefully. Back it up first:

```sh
run-as com.bachatas4.android sh -c '
D=files/runtime-home/.local/share/shadPS4
cp "$D/config.json" "$D/config.json.bak"
'
```

The relevant keys are inside the `General` section:

```json
{
  "General": {
    "connected_to_network": true,
    "shad_net_enabled": true,
    "shadnet_server": "100.101.102.103:31313",
    "shadnet_webapi_server": "http://100.101.102.103:31315",
    "signaling_info": "",
    "enable_upnp": false
  }
}
```

**Do not replace your entire real config with this small example.** It only shows the networking keys.

Replace `100.101.102.103` with the actual server Tailscale IPv4 address.

---

## 9. Android `host_overrides.json`

### Why Android needs a different override

The official PC shadp2p setup normally uses:

```text
thehuntersdream.com
```

directly.

In testing, the Android ARM64/FEX runtime could reach the Bloodborne community server by IPv4 but failed when its internal HTTP path used the hostname.

For that reason, the current Android workaround uses the current IPv4 address of:

```text
thehuntersdream.com
```

### Resolve the current IP

In normal Termux, outside `rish`:

```sh
pkg install dnsutils
dig +short thehuntersdream.com A | head -1
```

At the time this guide was written, the tested IPv4 was:

```text
162.243.148.146
```

**Do not assume this address will remain permanent.**

You can test it:

```sh
curl -v --connect-timeout 8 \
http://162.243.148.146:20443/bb-eu/ss.info \
-o /dev/null
```

A working endpoint should return HTTP `200`.

Port `18671` can also be checked:

```sh
curl -v --connect-timeout 8 \
-X POST \
http://162.243.148.146:18671/basic_utils/login \
-o /dev/null
```

A response such as `422` is okay for this test: it means the TCP/HTTP connection worked even though the manual request did not contain Bloodborne's real login body.

### Create the Android override

Create `/sdcard/Download/host_overrides.json` with:

```json
{
  "https://ss4.scej-network.jp:20443": "http://162.243.148.146",
  "http://thehuntersdream.com:18671": "http://162.243.148.146:18671",
  "http://thehuntersdream.com:18671/summon_messenger": "http://100.101.102.103:31315"
}
```

Replace:

```text
162.243.148.146
```

with the current `thehuntersdream.com` IPv4 if it changes.

Replace:

```text
100.101.102.103
```

with your shadNet server's Tailscale IP.

The specific `/summon_messenger` entry must continue pointing to **your shadNet WebAPI server**, not the public Bloodborne community server.

Copy the file into Bachata:

```sh
cat /sdcard/Download/host_overrides.json \
| run-as com.bachatas4.android sh -c \
'cat > files/runtime-home/.local/share/shadPS4/host_overrides.json'
```

Verify:

```sh
run-as com.bachatas4.android sh -c \
'cat files/runtime-home/.local/share/shadPS4/host_overrides.json'
```

---

## 10. Restart Bachata completely

After changing `config.json`, `users.json`, or `host_overrides.json`, stop Bachata:

```sh
am force-stop com.bachatas4.android
```

Then start Bachata normally.

Do not edit `host_overrides.json` while Bloodborne is already running and expect it to reload automatically.

---

## 11. Verify the shadNet server

Keep Tailscale connected.

From the Android browser or Termux:

```sh
curl http://<SERVER_TAILSCALE_IP>:31315/status
```

Expected:

```json
{"ok":true,"service":"shadnet-webapi"}
```

Then start Bloodborne in **Online** mode.

On the shadNet server, a successful connection should show the Android player's unique NPID authenticating and STUN pings appearing.

---

## 12. Verify Android logs

The Android log is:

```text
/data/user/0/com.bachatas4.android/files/runtime-home/.local/share/shadPS4/log/shad_log.txt
```

Useful check:

```sh
run-as com.bachatas4.android sh -c '
LOG=files/runtime-home/.local/share/shadPS4/log/shad_log.txt
grep -n -E "TCP connected|Login packet sent|Logged in|ApplyHostOverride|SUCCESS|TRANSPORT FAIL|Matching2|STUN" "$LOG" | tail -100
'
```

Good signs include:

```text
TCP connected
Login packet sent
Logged in
ApplyHostOverride
status=200
Matching2
```

---

## 13. Bloodborne co-op rules

For normal Bloodborne co-op:

- Host: **Beckoning Bell**
- Guest/helper: **Small Resonant Bell**
- Use the same matchmaking password when testing with a specific friend.
- Use two different shadNet accounts.
- Keep both devices in the same Tailscale tailnet.

Do **not** ring the Beckoning Bell on both devices if one player is supposed to join the other.

Server-side summon logs may show:

```text
Bloodborne summon: advertised user ...
Bloodborne summon: search ... returned 1
```

That proves the summon broker found a candidate.

### Current Android limitation

Even when the broker returns `1`, final co-op peer joining is not yet confirmed working in this Android ARM64 build.

General online functions can still work while the final co-op connection fails.

---

## Troubleshooting

### `You are not connected to PSN`

that's known issue and just close the emu and reopen it and it will be gone but in case it's not

Check:

- Tailscale is connected
- shadNet is running
- `users.json` is in the real runtime directory
- the NPID and password are valid and unique
- `shad_net_enabled` is enabled
- `shadnet_server` points to the server Tailscale IP on port `31313`

### `Failed to acquire Bloodborne server information`

Check the log for:

```text
ApplyHostOverride
```

The Android build should route:

```text
https://ss4.scej-network.jp:20443
```

to the current IPv4 for `thehuntersdream.com`.

Test the public service from Termux with `curl`.

### `Failed to log in to Bloodborne server`

Check that the generic port `18671` override also points to the current public IPv4:

```json
"http://thehuntersdream.com:18671": "http://CURRENT_IP:18671"
```

### Host override seems ignored

Make sure the file is here:

```text
files/runtime-home/.local/share/shadPS4/host_overrides.json
```

not here:

```text
/data/user/0/com.bachatas4.android/.local/share/shadPS4/
```

Restart Bachata after editing.

### shadNet login works but summon does not

Check:

- one player uses Beckoning Bell
- the other uses Small Resonant Bell
- different NPIDs
- same matchmaking password
- all peers appear in `tailscale status`
- every peer can `tailscale ping` every other peer
- server UDP `31314` is available
- the server reports `search ... returned 1`

If all of those work and the final join still fails, it is likely an Android ARM64/FEX compatibility issue rather than basic account or server setup.

---

## Security notes

- Never publish real account passwords.
- Never publish your private registration secret.
- Do not commit a real `users.json` if it contains credentials.
- A Tailscale `100.x.x.x` address is private to the tailnet, but you should still avoid publishing unnecessary private-network details.
- Keep backups of Bloodborne saves and the shadNet database.

---

## Credits

This Android setup is based on the work of the shadPS4, Bachata-S4, shadp2p, and shadNet/shadnet-p2p projects.

The Android-specific path, FEX compatibility work, and host-override workaround documented here are specific to this experimental Bachata-S4 ARM64 integration.
