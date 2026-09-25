# Godot 4.7: networking and export

Source: godot-docs branch 4.7 @9adca4c (2026-09-21). Read when: building the netcode (roadmap 25: `UserCmd`s up, snapshots down, prediction, lag compensation), a dedicated server, host and join menus (26), or an exported build (27).

## Rules for this project

- Use Godot's ENet as the **transport only**. Send your own bytes (tick-stamped `UserCmd` batches up, snapshots down) through `SceneMultiplayer.send_bytes()` and the `peer_packet` signal, or through `ENetConnection`/`ENetPacketPeer` directly. Do not build the game state on `@rpc` or `MultiplayerSynchronizer`/`MultiplayerSpawner`. The reasons are under "Why not the high-level replication".
- Receive and send inside `GameWorld`'s tick, not on the engine's schedule. Set `get_tree().multiplayer_poll = false` and call `multiplayer.poll()` yourself. The docs give this exact use: "running RPCs in a different loop (e.g. physics, thread, specific time step)" (`classes/class_scenetree.rst`). With raw ENet, call `ENetConnection.service(0)` in the tick until it returns `EVENT_NONE`, then `flush()` after the tick's sends.
- Snapshots and command batches go **unreliable** (`TRANSFER_MODE_UNRELIABLE`/`UNRELIABLE_ORDERED`, or ENet flags without `FLAG_RELIABLE`). Use **reliable** only for rare, must-arrive messages (connect handshake, chat, map change, the server's config), on a **different channel** from anything time-critical, so a resend cannot hold up snapshots (`classes/class_multiplayerpeer.rst`).
- Keep every unreliable packet under one MTU. ENet fragments larger packets. `FLAG_UNRELIABLE_FRAGMENT` exists to keep a too-big packet unreliable "even if the packet is too big and needs fragmentation (increasing the chance of it being dropped)" (`classes/class_enetpacketpeer.rst`), which implies that without it a fragmented unreliable packet is not sent unreliably (inferred). The docs give no ENet MTU number. Godot's own replication caps its sync packets at `max_sync_packet_size = 1350` bytes, so aim at about 1200 bytes a packet (inferred budget).
- Never decode objects from the network: `allow_object_decoding = false` (default) and `get_var(allow_objects=false)`. "Deserialized objects can contain code which gets executed" (`classes/class_scenemultiplayer.rst`, `classes/class_packetpeer.rst`). Better still, do not use `Variant` encoding for snapshots at all: write fixed binary with `StreamPeerBuffer` or `PackedByteArray.encode_*`.
- The server is the authority. "Treat all client input as untrusted": validate every `UserCmd` (angles in range, buttons known, one command per tick, a rate limit) before `run_command` (`tutorials/networking/high_level_multiplayer.rst`).
- Set `physics/common/physics_jitter_fix = 0.0` on server and client. The setting's docs recommend 0 "for network games, where clock synchronization matters" and for custom interpolation. Both apply here.
- A dedicated server is the same project run headless. Detect it with `DisplayServer.get_name() == "headless"`, `OS.has_feature("dedicated_server")` or a user argument (`OS.get_cmdline_user_args()`, after `--`), and build nothing to be seen (`reference/performance.md` "Next, in order" 1).
- An exported build cannot rely on what works from the editor: `FileAccess` and `DirAccess` on `res://`, and the `assets/` folder (see "Exporting").

## Why not the high-level replication (`classes/class_multiplayersynchronizer.rst`, `classes/class_scenereplicationconfig.rst`, `tutorials/networking/high_level_multiplayer.rst`)

- **It runs on frames, not ticks.** `MultiplayerSynchronizer.replication_interval` and `delta_interval` default to 0, meaning "every network process frame", and `SceneTree.multiplayer_poll` polls "during process_frame". The simulation runs at a fixed 64 Hz from `GameWorld`. Snapshots must be tick-stamped and match the tick the client interpolates and rewinds against. The synchronizer carries no tick number (inferred from its API: no tick or sequence member).
- **Its reliability modes are the wrong way round for state.** `REPLICATION_MODE_ALWAYS` sends every property "constantly" and unreliably. `REPLICATION_MODE_ON_CHANGE` sends changes "using reliable transfer mode". Neither is CS2's model: unreliable snapshots delta-compressed against the last snapshot the client acknowledged, so a loss costs nothing and nothing waits on a resend.
- **It replicates node properties by NodePath.** The simulation's state lives in `PlayerSim` (a `PlayerBody`), `MatchState`, `GameSystems` and `RefCounted` entities, not in a tree laid out for replication. "Synchronization is not supported for Object type properties", and RIDs or instance IDs are meaningless on another peer.
- **RPCs are node calls with strict pairing.** An RPC needs the same `NodePath` on both ends (use `add_child(node, true)` for readable names). A checksum covers **all** `@rpc` declarations in a script, so client and server must declare every RPC identically, even unused ones. RPCs do not serialize Objects or Callables. `get_remote_sender_id()` identifies the sender. They are fine for rare messages (a lobby, a map change) and wrong for per-tick traffic, where the payload is the command and its tick (inferred).
- **What to use instead, lowest level last:**
  1. `SceneMultiplayer.send_bytes(bytes: PackedByteArray, id=0, mode=TRANSFER_MODE_RELIABLE, channel=0)` with the signal `peer_packet(id, packet)`. You keep `MultiplayerAPI`'s peer IDs, connect and disconnect signals, and authentication (`auth_callback`, `send_auth`, `complete_auth`, `auth_timeout = 3.0`), and choose mode and channel per packet. Note that the default mode is **reliable**.
  2. `MultiplayerPeer` itself (a `PacketPeer`): `transfer_mode`, `transfer_channel`, `set_target_peer(id)`, `put_packet()`, then `get_packet()` with `get_packet_peer()`, `get_packet_channel()` and `get_packet_mode()`.
  3. `ENetConnection` + `ENetPacketPeer` (the raw wrapper): per-packet flags, per-peer RTT and loss statistics, timeouts, throttle and compression. `ENetMultiplayerPeer.host` exposes the connection behind a high-level peer, and `get_peer(id)` gives an `ENetPacketPeer`.
  4. `PacketPeerUDP` + `UDPServer`: bare UDP, when you write your own reliability.

## ENet in Godot (`classes/class_enetmultiplayerpeer.rst`, `classes/class_enetconnection.rst`, `classes/class_enetpacketpeer.rst`)

- UDP only. Forward the server port as UDP. It supports IPv6 (Godot's modified ENet).
- `ENetMultiplayerPeer.create_server(port, max_clients=32, max_channels=0, in_bandwidth=0, out_bandwidth=0) -> Error`: up to 4095 clients, binds `"*"` (all interfaces) unless `set_bind_ip(ip)` is called first. Returns `ERR_ALREADY_IN_USE` if already open (call `close()` first) or `ERR_CANT_CREATE`.
- `create_client(address, port, channel_count=0, in_bandwidth=0, out_bandwidth=0, local_port=0) -> Error`: the address is a domain or an IPv4 or IPv6 address. Bandwidth in bytes per second, 0 = unlimited. The bandwidth values also set the window, which limits reliable packets in flight. `local_port` is for NAT traversal.
- The docs do not say what `max_channels = 0` or `channel_count = 0` resolve to. Pass an explicit count when you use channels beyond 0.
- **Channels.** In the high-level peer, "the default channel (0) actually works as 3 separate channels (one for each TransferMode)", so reliable and unreliable-ordered do not block each other on channel 0 (`classes/class_multiplayerpeer.rst`). Reliable traffic blocks only its own channel, and ordering holds only within a channel. For raw ENet, a workable plan is: channel 0 for unreliable snapshots and commands, and channel 1 for reliable control and chat (inferred design).
- **Modes.** `TRANSFER_MODE_UNRELIABLE` (0): no acks, no resends, any order. `TRANSFER_MODE_UNRELIABLE_ORDERED` (1): no resends, and late packets are dropped if a newer one arrived. It "can cause packet loss if used incorrectly": keep packets on one ordered channel similar in size. `TRANSFER_MODE_RELIABLE` (2, the **default** `transfer_mode`): resent until acked, in order, with "a significant performance penalty".
- Raw flags on `ENetPacketPeer.send(channel, packet, flags)` and `ENetConnection.broadcast(channel, packet, flags)`: `FLAG_RELIABLE = 1`, `FLAG_UNSEQUENCED = 2` (unreliable and unordered), `FLAG_UNRELIABLE_FRAGMENT = 8`. With flags 0, a packet is unreliable but sequenced (inferred from ENet's own semantics; the docs describe only the three flags).
- `ENetConnection.create_host_bound(bind_address, bind_port, max_peers=32, max_channels=0, in_bandwidth=0, out_bandwidth=0)` for a server, `create_host(...)` for a client (random port), then `connect_to_host(address, port, channels=0, data=0) -> ENetPacketPeer`. Both ends need a host.
- `service(timeout=0) -> Array` returns `[EventType, ENetPacketPeer, data, channel]`. `EVENT_RECEIVE` queues the packet on that peer (read it with `peer.get_packet()`). A timeout of 0 is the non-blocking poll to call in the tick. "Must be called on both ends". `flush()` sends queued packets now rather than at the next `service`.
- `compress(mode)`: `COMPRESS_NONE`, `COMPRESS_RANGE_CODER` (ENet's own, good for packets under 4 KB), `COMPRESS_FASTLZ`, `COMPRESS_ZLIB`, `COMPRESS_ZSTD`. It must be the same on server and every client, or connections fail.
- Statistics: `ENetPacketPeer.get_statistic(PEER_ROUND_TRIP_TIME)` (mean RTT of reliable packets, ms), `PEER_PACKET_LOSS` (a ratio of `PACKET_LOSS_SCALE = 65536`), and the variances. `ENetConnection.pop_statistic(HOST_TOTAL_SENT_DATA / ...)` returns and resets. Useful for choosing the interpolation buffer from RTT jitter.
- `ENetPacketPeer.set_timeout(timeout, timeout_min, timeout_max)` (ms), `ping_interval(ms)` (default 500), and `throttle_configure(interval, acceleration, deceleration)`. The throttle **drops unreliable packets on purpose** when RTT fluctuates. At `PACKET_THROTTLE_SCALE` (32) nothing is dropped. Watch for it before blaming the netcode for loss.
- DTLS: `dtls_server_setup(TLSOptions)` / `dtls_client_setup(...)` right after creating the host.
- `socket_send(address, port, packet)` punches NAT holes from the bound socket (needs STUN, and never works through symmetric NAT). `ENetMultiplayerPeer.create_mesh` / `add_mesh_peer` is peer-to-peer. Neither is needed for a dedicated server.
- `MultiplayerPeer.poll()`: the class ref says it "waits up to 1 second to receive a new network event". Do not call it inside the tick until that is checked. `MultiplayerAPI.poll()` (which the SceneTree calls) is the normal path.

## MultiplayerAPI and SceneMultiplayer (`classes/class_multiplayerapi.rst`, `classes/class_scenemultiplayer.rst`, `tutorials/networking/high_level_multiplayer.rst`)

- Each node's `multiplayer` is the tree's `MultiplayerAPI` (a `SceneMultiplayer`), unless `get_tree().set_multiplayer(api, root_path)` gives a branch its own. With that and `SceneMultiplayer.root_path`, a server and a client can run in **one process**. That makes a headless test of connect, command and snapshot possible without two Godot instances (inferred use).
- Assign a peer with `multiplayer.multiplayer_peer = peer`. To tear down, set `OfflineMultiplayerPeer.new()`.
- The server's peer ID is always 1. Clients get a random positive ID. `get_unique_id()`, `is_server()`, `get_peers()`, `get_remote_sender_id()`.
- Signals: `peer_connected(id)` and `peer_disconnected(id)` on all peers. `connected_to_server`, `connection_failed` and `server_disconnected` on clients only. With authentication, `peer_authenticating(id)` and `peer_authentication_failed(id)` fire, and the connection counts as established only after both sides call `complete_auth`. (The tutorial writes `auth_timout`; the property is `auth_timeout`.)
- `server_relay = true` (default) lets the server tell clients about each other and relay client-to-client packets. Turn it off for a dedicated server that alone talks to each client.
- `max_sync_packet_size = 1350` and `max_delta_packet_size = 65535` apply only to `MultiplayerSynchronizer`.
- `refuse_new_connections` (on the peer or on `SceneMultiplayer`) is for a full server.

## Serializing (`classes/class_streampeerbuffer.rst`, `classes/class_streampeer.rst`, `classes/class_packedbytearray.rst`)

- `StreamPeerBuffer` writes into a byte array with a cursor: `put_u8/u16/u32/u64`, `put_8/16/32/64`, `put_half` (16-bit float), `put_float`, `put_double`, `put_data(bytes)`, and the matching `get_*`. `seek(pos)`, `get_position()`, `get_size()`, `resize()`, `clear()`. `big_endian = false` by default.
- Gotcha: `StreamPeerBuffer.data_array` returns a **copy**. Setting it resets the cursor.
- `PackedByteArray.encode_u16/encode_float/encode_half(offset, value)` and `decode_*` write in place into a pre-sized array. `compress()`/`decompress()` exist for whole-buffer compression.
- `put_var`/`var_to_bytes` include a type header per value and grow toward a power of two, up to `encode_buffer_max_size` (8 MiB). Fine for the lobby, wasteful for 64 Hz snapshots (inferred).

## Other transports (`tutorials/networking/websocket.rst`, `webrtc.rst`, `http_request_class.rst`)

- `WebSocketMultiplayerPeer` and `WebRTCMultiplayerPeer` implement the same `MultiplayerPeer`. WebSocket is TCP and reliable only, wrong for snapshots. WebRTC matters only for the web. `HTTPRequest` could fetch a server list later. None is needed for roadmap 25.

## The dedicated server (`tutorials/export/exporting_for_dedicated_servers.rst`, `tutorials/editor/command_line_tutorial.rst`, `classes/class_displayserver.rst`)

- `--headless` means `--display-driver headless --audio-driver Dummy`. It works with editor or export-template binaries, and the docs recommend a template binary for a server (smaller, faster). There is no separate server binary since 4.0.
- Detecting server mode, in `_ready()` of the main scene or an autoload:
  - `OS.has_feature("dedicated_server")`: set by the "Export as dedicated server" mode, or by adding `dedicated_server` to the preset's custom features. That custom tag also **forces `--headless`**. It is only true in the exported project, never from the editor.
  - `DisplayServer.get_name() == "headless"`, when started with `--headless`.
  - `"--server" in OS.get_cmdline_user_args()` (arguments after `--`). `maps/play/play.gd:49` already reads `--map` this way.
- **Export as dedicated server** (a preset's Resources tab) replaces visual resources with placeholders: Cubemap, CubemapArray, **Material, Mesh**, Texture2D, Texture2DArray and Texture3D. A placeholder texture keeps only its size. Per file or folder: **Strip Visuals**, **Keep** or **Remove**. Remove breaks any scene that references the file. Audio has no placeholder yet, so exclude it by not referencing it, and load it by `load()` on the client only.
- Consequence here (inferred): `MapImporter._build_collision` builds the world's collision at load from `mesh_instance.mesh.get_faces()` (`src/map/map_importer.gd:534`). A stripped `Mesh` placeholder has no faces, so a server export must **Keep** the collision glTFs' meshes, or collision must be baked into saved `ConcavePolygonShape3D` resources at import time (`Shape3D` is not in the stripped list).
- A headless process has no V-Sync, so the main loop is capped only by `Engine.max_fps` (default 0 = uncapped) or `--max-fps` (inferred: an uncapped headless server spins a core between ticks). Give the server a cap, for example the tick rate or twice it. Physics still steps at `physics_ticks_per_second = 64`, with up to `max_physics_steps_per_frame` (16 here) catch-up steps per frame.
- For systemd logging, set `application/run/flush_stdout_on_print = true` (it is off by default in release builds).
- Audio: the Dummy driver takes the place of sound output. Code that loads sounds still loads them unless the server path skips it.

## Exporting (`tutorials/export/exporting_projects.rst`, `tutorials/export/exporting_pcks.rst`, `tutorials/export/feature_tags.rst`)

- Presets live in `export_presets.cfg` (safe to commit). Secrets live in `.godot/export_credentials.cfg` (do not commit). Export templates must be installed for the exact engine version. The repo has no `export_presets.cfg` yet.
- Command line: `godot --headless --path <project> --export-release "<preset>" <out>`, `--export-debug`, `--export-pack "<preset>" out.pck|out.zip` (data only), and `--export-patch` with `--patches a.pck,b.pck`. **Output paths are relative to the project directory, not the shell's current directory**, and the target directory must already exist. The table says `--export-debug` and `--export-pack` imply `--import`. It is not stated for `--export-release`, so run `--import` first in a fresh checkout (the tests already do).
- Resource export modes: all resources; selected scenes; selected resources; all except checked; dedicated server. Files and folders starting with `.` are never exported. **Non-resource files** (`.txt`, `.json`, `.csv`, and here also `.md`, `.nav` and `.vmat`) are exported **only** if they match the preset's include filter.
- PCK is uncompressed and fast. ZIP is compressed and needs a launcher with `--main-pack` because of a known bug. A PCK next to a template binary of the same name runs as the game.
- Extra packs: `ProjectSettings.load_resource_pack(path, replace_files=true)`. A pack's files replace same-named ones unless you pass `false`. Load packs early (an autoload's `_init()`), before anything `preload`s. A pack can be a whole second project.
- In an exported project, `res://` holds converted files. "Some files are converted to engine-specific formats and their original source files may not be present", so the docs recommend `ResourceLoader` over `FileAccess`. To list resources by their editor names use `ResourceLoader.list_directory(path)`, since `DirAccess` sees the remapped files (`classes/class_diraccess.rst`, `classes/class_resourceloader.rst`).
- Feature tags: `OS.has_feature(tag)` is case-sensitive. The built-in tags (`windows`, `linux`, `pc`, `debug`, `release`, `editor`, `template`, `x86_64`, `dedicated_server`, `shader_baker`, and so on) are immutable. Custom tags from a preset work only in the exported run, never from the editor. Project settings can be overridden per tag (`setting.tag=value`), but `ProjectSettings.get_setting()` ignores overrides. Use `get_setting_with_override()`.
- Roadmap 27 says "the extracted assets stay outside" the build. Imported assets live as converted files under `.godot/imported`, and a build finds them only through a pack. A workable plan is two packs from two presets (inferred design): the game (code, `reference/` data) as the main PCK, and `assets.pck` exported on Sid's machine with an "only `assets/`" preset, loaded by `load_resource_pack` in an autoload's `_init()`. Never distribute the assets pack, since it is Valve's content.

## Class notes

**MultiplayerAPI**: `multiplayer_peer`, `get_unique_id()`, `is_server()`, `get_peers()`, `get_remote_sender_id()`, `poll() -> Error` (RPCs run in its context), `has_multiplayer_peer()`, `object_configuration_add/remove` (used by the Spawner and Synchronizer), and the signals above.

**SceneMultiplayer**: `send_bytes(bytes, id=0, mode=2, channel=0)`, signal `peer_packet(id, packet)`, `auth_callback`, `auth_timeout = 3.0`, `send_auth(id, data)`, `complete_auth(id)`, `get_authenticating_peers()`, `disconnect_peer(id)`, `server_relay = true`, `allow_object_decoding = false`, `refuse_new_connections`, `root_path`, `max_sync_packet_size = 1350`, `max_delta_packet_size = 65535`. Its protocol "isn't meant to be used by non-Godot servers" and may change.

**MultiplayerPeer**: `transfer_mode = TRANSFER_MODE_RELIABLE (2)`, `transfer_channel = 0`, `set_target_peer(id)` (`TARGET_PEER_BROADCAST = 0`, `TARGET_PEER_SERVER = 1`, a negative id means everyone but that peer), `get_packet_peer()`, `get_packet_channel()`, `get_packet_mode()`, `get_connection_status()`, `disconnect_peer(id)`, `close()`, `refuse_new_connections`, `is_server_relay_supported()`, and the signals `peer_connected` and `peer_disconnected`.

**ENetMultiplayerPeer / ENetConnection / ENetPacketPeer**: see "ENet in Godot". `ENetPacketPeer` states run from `STATE_DISCONNECTED` to `STATE_ZOMBIE`, plus `get_remote_address()`, `get_remote_port()`, `peer_disconnect(data)`, `peer_disconnect_later`, `peer_disconnect_now`, `ping()` and `reset()`.

**PacketPeerUDP** (`classes/class_packetpeerudp.rst`): `bind(port, bind_address="*", recv_buf_size=65536)` (`"*"` means IPv4 and IPv6; `"0.0.0.0"` means IPv4 only), `set_dest_address(host, port)`, `connect_to_host(host, port)` (filters incoming by address and fixes the destination; sends nothing), `put_packet`, `get_packet`, `get_packet_ip()`, `get_packet_port()`, `get_available_packet_count()`, `wait()` (blocks and cannot be interrupted), `set_broadcast_enabled`, and `join_multicast_group`. Connecting "does not help to protect from ... IP spoofing".

**UDPServer** (`classes/class_udpserver.rst`): `listen(port, bind_address="*")`, `poll()` (call regularly), `is_connection_available()`, `take_connection() -> PacketPeerUDP`, and `max_pending_connections = 16` (0 refuses new clients).

**StreamPeerBuffer**: see "Serializing".

**MultiplayerSynchronizer / MultiplayerSpawner** (only if used for something non-critical, such as a lobby): `root_path`, `replication_config` (`SceneReplicationConfig.add_property(path)` and `property_set_replication_mode(path, REPLICATION_MODE_NEVER/ALWAYS/ON_CHANGE)`), `replication_interval`, `delta_interval`, `public_visibility`, `set_visibility_for(peer, visible)`, `add_visibility_filter(callable)`, `update_visibility()`, and `visibility_update_mode` (`IDLE`/`PHYSICS`/`NONE`). Spawner: `spawn_path`, `add_spawnable_scene(path)`, `spawn_function`, `spawn(data)`, `spawn_limit`, and the signals `spawned` and `despawned`.

**OS** (`classes/class_os.rst`): `has_feature(tag)`, `get_cmdline_args()` (excludes engine arguments such as `--headless`), and `get_cmdline_user_args()` (after `--` or `++`).

**DisplayServer**: `get_name()` (`"headless"` under `--headless`), `window_set_vsync_mode(mode)` (`VSYNC_DISABLED`/`ENABLED`/`ADAPTIVE`/`MAILBOX`; Forward+ supports all), `window_set_mode(WINDOW_MODE_EXCLUSIVE_FULLSCREEN)`, and `screen_get_refresh_rate()` (-1 on failure).

**Engine**: `max_fps = 0` (uncapped; V-Sync Enabled or Adaptive takes precedence), `physics_jitter_fix = 0.5` (set 0 for networking), `max_physics_steps_per_frame`.

## Where the code already does this

- No networking code exists yet: no `MultiplayerPeer`, `ENet*`, `PacketPeerUDP`, `@rpc` or `multiplayer` use in `src/`, `maps/` or `scripts/` (checked with grep). `UserCmd` (`src/sim/user_cmd.gd`) and `GameWorld` (`src/sim/game_world.gd`) are the shapes the netcode will carry. `GameWorld.step()` is where receiving (before the players' commands) and sending (after `end_tick`) would go.
- `maps/play/play.gd:49` reads `--map` from `OS.get_cmdline_user_args()` and falls back to `get_cmdline_args()`. That is the pattern for `--server` and `--connect`.
- Headless runs: `scripts/run_tests.sh` and every `scripts/*.gd` tool run `godot --headless --path . --script ...`.
- There is no `export_presets.cfg` in the repo yet (roadmap 27).

Looks at odds with the docs for an exported build (not verified; nothing is exported yet):
- `src/audio/sound_bank.gd:23,36` lists `res://assets/sounds/...` with `DirAccess` and keeps `.wav`/`.mp3`/`.ogg` names. In an export, the originals are replaced by remapped or imported files, so the listing will not find them (`classes/class_diraccess.rst`). `ResourceLoader.list_directory()` returns the editor-visible names. `src/map/map_importer.gd:190` (`_list_gltfs`, used by `MapImporter.find_map_file`) has the same problem for `.gltf`.
- These `FileAccess` reads of non-resource files under `res://` are missing from an export unless the preset's non-resource include filter covers them: `src/weapons/weapon_library.gd:195,235` (`reference/weapons/*.md`), `src/weapons/weapon_vdata.gd:117` and `src/weapons/weapon_sheet.gd:129` (`.csv`), `src/weapons/recoil_pattern.gd:33` (`reference/spray_patterns`), `src/audio/weapon_sounds.gd:312`, `src/combat/hitbox_set.gd:70`, `src/map/map_overview.gd:35`, `src/map/source_nav_mesh.gd:179` (`.nav`), `src/map/map_loader.gd:147` and `src/combat/bullet_impacts.gd:130` (`.vmat` text), and `src/effects/sprite_sheet.gd:37` (`.sheet.json`).
- `src/map/map_importer.gd:534` builds collision from `Mesh.get_faces()` at runtime. That is empty under "Export as dedicated server" unless those meshes are marked Keep (above).
- `project.godot` leaves `physics/common/physics_jitter_fix` at 0.5. The docs say 0 for network games.

## Not covered here

- HTTP (`tutorials/networking/http_request_class.rst`, `http_client_class.rst`) and TLS certificates (`ssl_certificates.rst`).
- WebRTC signalling (`tutorials/networking/webrtc.rst`) and the WebSocket API (`websocket.rst`).
- Platform export pages: `tutorials/export/exporting_for_windows.rst` (code signing, icon) and `exporting_for_linux.rst`. Shader baking at export (`shader_baker`): see `tutorials/performance/pipeline_compilations.rst` and the rendering page.
- UPnP port forwarding (`classes/class_upnp.rst`), mentioned by `ENetMultiplayerPeer`.
- Encrypting the PCK (needs a custom-built template): `tutorials/export/exporting_pcks.rst` and the compiling docs.
