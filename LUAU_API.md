# Divinity Luau API reference

This is the complete reference for the scripting API the DLL exposes to Luau
scripts. It is written from the native bindings:

| Global | Source |
|---|---|
| `print`, `warn`, `events`, `hooks` | `core/luau_runtime.cpp` |
| `rage.scan`, `rage.knife_scan`, `rage.resolver` | `features/combat/aimbot_lua.cpp` |
| `rage.antiaim` | `features/combat/hvh_lua.cpp` |
| `ui` | `gui/script_ui.cpp` |
| `settings` | `core/script_settings.cpp` |
| `indicators` | `features/visuals/indicators.cpp` |
| `client` | `core/client_api.cpp` |
| `sound` | `features/visuals/sounds.cpp` |

Hook contexts are built in `aimbot_lua.cpp`, `hvh_lua.cpp`, `resolver.cpp`
and `shots.cpp`. Event payloads come from `client_api.cpp`, `grenades.cpp`,
`lagcomp.cpp`, `script_ui.cpp` and `script_settings.cpp`. If this document
and the code disagree, the code is right; please update this file.

## Contents

1. [Runtime and lifecycle](#1-runtime-and-lifecycle)
2. [Conventions](#2-conventions)
3. [Console output: `print`, `warn`](#3-console-output)
4. [`events`](#4-events)
5. [`hooks`: stage hooks](#5-hooks-stage-hooks)
6. [Ragebot stages](#6-ragebot-stages)
7. [Resolver stages](#7-resolver-stages)
8. [Anti-aim stages](#8-anti-aim-stages)
9. [`rage`](#9-rage)
10. [`rage.antiaim`](#10-rageantiaim)
11. [`ui`](#11-ui)
12. [`settings`](#12-settings)
13. [`indicators`](#13-indicators)
14. [`client`](#14-client)
15. [`sound`](#15-sound)
16. [Enumerations](#16-enumerations)
17. [Files on disk](#17-files-on-disk)
18. [Examples](#18-examples)

---

## 1. Runtime and lifecycle

- **Engine.** The DLL embeds Luau 0.740 (VM and compiler). It is not LuaJIT
  or PUC Lua. `.lua` and `.luau` files are compiled with the same Luau
  compiler.
- **Script directory.** `Documents\Divinity\Scripts`, resolved through the
  Windows Documents known folder, so OneDrive and other folder redirection
  work. The directory is created if it is missing.
- **Discovery.** Top-level files ending in `.luau` or `.lua` are listed.
  Files ending in `.d.luau` or `.d.lua` are type declarations and are never
  loaded. A valid name has at most 255 bytes, does not start with `.`, and
  contains no control characters or `\ / : * ? " < > |`. Sources over 2 MiB
  are rejected.
- **Enabled scripts.** `loaded_scripts.cfg` remembers which scripts are
  enabled. Only enabled scripts load at startup, in filename order. With no
  manifest, no scripts are enabled.
- **One VM, separate globals.** All scripts share one Luau VM. Each script
  runs in its own sandboxed thread with its own global environment. The
  standard Luau libraries are available (`math`, `string`, `table`,
  `coroutine`, `bit32`, `utf8`, `buffer`, `vector`, `os`, `debug`, plus the
  base library). FFI and raw memory access are not available.
- **Read-only API.** The host tables `ui`, `events`, `rage`, `settings`,
  `indicators`, `client` and `sound` are frozen, along with their nested
  tables and metatables. A script can shadow a global in its own environment
  but cannot change the shared API.
- **Thread.** Everything runs on the VM owner thread. Load, unload, reload
  and refresh requests from the **Scripts** tab are queued and run at the
  start of the next menu paint frame. They work outside a match.
- **Limits.** Scripts have no execution-time or memory quota. A slow
  callback stalls the game.

### Errors

- A compile error or runtime error during load is reported. The failed load
  leaves no controls, callbacks or hooks behind. Its UI values and settings
  are restored to what they were before the load.
- A callback (`events.*`) that raises an error is **unregistered** for that
  script. The error is logged as `events.<name>: <message>`.
- A hook that raises an error is **unhooked** for that script. The error is
  logged as `failed in <stage> (<message>.)`.
- Errors go to the in-game developer console and to the Windows debugger
  output. The Scripts tab also shows the latest error for each file.

### Load, unload and reload

| Action | Effect |
|---|---|
| **Load** | Enables the script for future sessions, then runs it. |
| **Unload** | Disables the script for future sessions, then releases it. |
| **Reload** | Unload, then load. The enabled flag is unchanged. If the reload fails, the script stays unloaded. |
| **Refresh list** | Finds new files. Does not enable or load anything. |
| **Reload loaded** | Reloads every loaded script and nothing else. |

Releasing a script runs these steps in order:

1. Its `events.shutdown` callback runs, if it registered one. Its controls
   are still valid at this point.
2. Committed control values and settings are written to disk.
3. Borrowed native state is restored: manual anti-aim direction, resolver
   overrides, hidden built-in menu elements, twist movement flags.
4. Its controls, groups, indicators, callbacks, hooks and thread are freed.

When several scripts unload at once, they unload in reverse load order. During
shutdown a script can still read and set its existing controls, but it cannot
create controls, open settings or register callbacks.

---

## 2. Conventions

- **Dot or colon.** Unless a section says otherwise, call functions with a
  dot: `rage.scan(...)`, `ui.create(...)`. Handle methods use a colon:
  `control:get()`. Functions documented as accepting both forms work either
  way.
- **Player index.** Players are identified by entity index, 1 to 64.
- **Angles** are in degrees. Yaw outputs are normalised to (-180, 180].
- **Validation.** Hook results and most setters ignore values with the
  wrong type, values that are not finite, and values that are out of range.
  An ignored field keeps the native value. Nothing raises an error for a
  bad field unless this document says so.
- **Ownership.** Handles (controls, groups, settings, indicators) belong to
  the script that created them. Calling one from another script does nothing,
  or returns `nil`.

---

## 3. Console output

```lua
print(...)
warn(...)
```

Both replace the Luau builtins. Arguments are converted with `tostring`
rules (including `__tostring`) and joined with tabs. Lines are written to the
developer console tagged with the calling script, in the format
`[divinity][<script>.luau] <message>`. `warn` uses the warning level. `%` is
printed literally. Embedded NULs are shown as `\0`.

---

## 4. `events`

Events are notifications. They pass one table argument and ignore return
values. The one exception is `grenade`, which reads `release` back.

```lua
events.<name>:set(function(event) ... end)
events.<name>:unset()
```

`set` and `unset` use a **colon**. Each script has at most one callback per
event; calling `set` again replaces it. Calling either outside an active
script raises an error.

Events are not delivered while a script is loading or unloading, or while a
hook or another event is being dispatched.

| Event | Fires | Read-only | Who receives it |
|---|---|---|---|
| `tick` | every command | no | every script |
| `grenade` | every command while a grenade is being primed | no (`release` is read back) | every script |
| `animation` | each new enemy animation record | yes | every script |
| `ui` | a script control changed by the user, or a button was clicked | yes | the owning script only |
| `settings` | a settings namespace was committed | yes | the owning script only |
| `shutdown` | the script is being released | yes | that script only |

### `tick`

Fires at the start of every command, before the native features run. It also
fires when you are not alive.

| Field | Type | Meaning |
|---|---|---|
| `time` | number | Engine real time, in seconds. |
| `command_number` | number | User command number. |
| `alive` | boolean | Local player exists and is alive. |
| `in_game` | boolean | Engine reports in game. |

### `grenade`

Fires on every command while you hold a grenade with attack or attack2 held
and the trajectory simulation produced a path. It fires even when the
**Nades** visual is off.

| Field | Type | Meaning |
|---|---|---|
| `weapon_id` | number | Item definition index of the grenade. |
| `power` | number | Throw strength, from 0 to 1. |
| `fuse_time` | number | Simulated flight time, in seconds. |
| `end_x`, `end_y`, `end_z` | number | Predicted landing or detonation point. |
| `damage` | number | HE only: highest damage dealt to one enemy. 0 for other grenades. |
| `total_damage` | number | HE only: summed damage to enemies. |
| `self_damage` | number | HE only: damage to yourself. |
| `enemies_hit` | number | HE only: number of enemies damaged. |
| `kills` | number | HE only: number of enemies killed. |
| `lob` | boolean | Attack2 is held. |
| `release` | boolean | Writable, starts `false`. Set it to `true` to clear attack and attack2 on this command, which throws the grenade. |

### `animation`

Fires for each enemy record after the animation fix ran its prediction. It
compares the layers the server sent against the layers that were predicted.
Optional fields are present only when they apply.

| Field | Type | Meaning |
|---|---|---|
| `index` | number | Player index. |
| `mode` | number | Internal resolver mode (see [Enumerations](#16-enumerations)). |
| `lag` | number | Choked ticks. |
| `speed` | number | Horizontal animation velocity. |
| `guesses` | number | Number of simulated yaw guesses. |
| `on_ground` | boolean | Record is on the ground. |
| `move_sequence_match` | boolean? | Move layer (6) sequences match. Present when either move layer has weight. |
| `move_weight_error` | number? | Absolute weight difference of layer 6. |
| `move_cycle_error` | number? | Wrapped cycle distance of layer 6. Only when the sequences match. |
| `move_rate_error` | number? | Playback rate difference of layer 6. Only when the sequences match. |
| `adjust_activity_match` | boolean? | Adjust layer (3) activities match. Present when either adjust layer has weight. |
| `adjust_weight_error` | number? | Weight difference of layer 3. |
| `adjust_cycle_error` | number? | Cycle difference of layer 3. Only when the activities match. |
| `best_guess_move_cycle_error` | number? | Move-cycle error of the best yaw guess. |
| `tracker_offset` | number? | Tracker yaw minus resolved yaw. |
| `tracker_confidence` | number? | Tracker confidence. |
| `tracker_breaker` | number? | Tracker breaker estimate. |

### `ui`

Sent only to the script that owns the control. Fires from the menu service
step when the user changes a script control's value or clicks a script
button. Values set with `:set()` and values loaded from disk do not fire it.

| Field | Type | Meaning |
|---|---|---|
| `owner` | string | Owning script filename. |
| `handle` | number | The control's `__handle`. |
| `kind` | string | `"change"` or `"click"`. |
| `value` | boolean or number | Changes only. Switch: boolean. Slider: number. Combo: one-based index. Multi-combo: bitmask. Hotkey: key code. |

### `settings`

Sent only to the owning script, after one of its namespaces is committed with
`:set()`.

| Field | Type | Meaning |
|---|---|---|
| `owner` | string | Owning script filename. |
| `namespace` | string | The namespace name. |
| `reason` | string | Always `"change"`. |

### `shutdown`

Runs during release (see [Load, unload and reload](#load-unload-and-reload)).

| Field | Type | Meaning |
|---|---|---|
| `reason` | string | `"reload"`, `"unload"`, `"shutdown"` or `"load_failed"`. |
| `loaded` | boolean | `false` when the load failed. |

Shutdown callbacks do not run when the process exits or crashes.

---

## 5. `hooks`: stage hooks

The ragebot, resolver and anti-aim are split into stages. A script can hook a
stage to watch it, adjust it or replace it. A stage with no hook runs natively
and costs no Lua time.

```lua
hooks.set(stage, function(ctx) ... end)   -- register or replace this script's hook
hooks.unset(stage)                         -- remove this script's hook
hooks.owner(stage) --> string?             -- the script with the final say, or nil
hooks.stages       --> { string }          -- every stage name, read-only
```

`hooks.set` and `hooks.unset` raise an error when the stage name is unknown or
when they are called outside an active script.

### Stage list

| Stage | Runs | Section |
|---|---|---|
| `ragebot.target` | when the weapon is ready, to pick a target | [6](#ragebottarget) |
| `ragebot.stop` | every tick, before target choice | [6](#ragebotstop) |
| `ragebot.fire` | after hitchance, to decide whether to fire | [6](#ragebotfire) |
| `ragebot.shot` | after a target is chosen, for shot style | [6](#ragebotshot) |
| `ragebot.knife` | while holding a knife | [6](#ragebotknife) |
| `resolver.resolve` | for each enemy record | [7](#resolverresolve) |
| `resolver.feedback` | when a shot is finalised | [7](#resolverfeedback) |
| `antiaim.view` | every command, for the base view yaw | [8](#antiaimview) |
| `antiaim.angles` | every command, for the final angles | [8](#antiaimangles) |
| `antiaim.breaker` | when the standing LBY breaker runs | [8](#antiaimbreaker) |
| `antiaim.twist` | when the moving twist runs | [8](#antiaimtwist) |
| `antiaim.packet` | every command, to choose send or choke | [8](#antiaimpacket) |
| `antiaim.enemy_shot` | when an enemy's shot at you is finalised | [8](#antiaimenemy_shot) |

### The context table

Each call builds one `ctx` table, which every hooked script receives in turn.
It holds:

- the stage's inputs (listed per stage below);
- `ctx.stage`: the stage name;
- `ctx.result`: the result table (`nil` until something sets it);
- `ctx:original()`: runs the native stage.

A hook can do one of three things:

- **Observe.** Read fields and return. If nothing sets a result or calls
  `original()`, the native stage runs as if it were not hooked.
- **Tweak.** Edit editable inputs, call `ctx:original()`, then optionally
  edit the table it returns. That table is also stored in `ctx.result`.
- **Replace.** Assign `ctx.result = { ... }` without calling `original()`.

Rules:

- `ctx:original()` must be called **with a colon**. The host reads the
  edited inputs from `ctx` before running native code. **Editable inputs only
  take effect through `original()`**: editing them without calling it does
  nothing.
- `original()` runs native code at most once per call. Later calls, including
  calls from later scripts in the chain, return the same cached table.
  Observe-only stages return `nil`.
- After every hook has run, the host applies `ctx.result` if it is a table.
  If it is not, the host applies the cached `original()` result. Fields that
  are missing, of the wrong type or out of range keep their native value.
  So `ctx.result = {}` suppresses the native stage without changing
  anything.
- Values returned from a hook function are ignored. Results are read only
  from `ctx.result`.

### Chaining

Hooks on a stage run in script load order. Each script sees the previous
script's `ctx.result`, and the last script has the final say.
`hooks.owner(stage)` returns that last script. Whenever a stage's chain
changes, every script that is not last gets a console warning, for example
`hooked ragebot.target without full priority (runs 1st of 3, so c.luau has the final say.)`.

A stage cannot run inside itself. Different stages can nest: for example, an
`antiaim.angles` hook that calls `original()` still runs the
`antiaim.view`, `antiaim.breaker` and `antiaim.twist` hooks.

### Native safety applied after every chain

These are enforced whatever a script returns:

- The packet is forced to send at the maximum choke, on a fresh jump, and on
  shot commands. A choke that the final packet logic forbids is undone.
- Pitch outputs are clamped to ±89 (`safe_pitch` is always `true`).
- Anti-aim angles are applied only while angles are allowed (not while
  attacking, using, on a ladder, in noclip, frozen, during freeze time, after
  round end, or while a grenade is being thrown).
- Resolver results are ignored on shot records, while a manual override is
  set, and on direct LBY updates.
- Trace, damage, hitchance and fire-command checks stay native.

---

## 6. Ragebot stages

### Shared ragebot context

`ragebot.target`, `ragebot.stop` and `ragebot.knife` receive this context:

| Field | Type | Meaning |
|---|---|---|
| `targets` | table | Enemies keyed by **player index** (a sparse table, so iterate with `pairs`). See below. |
| `weapon_id` | number | Item definition index. |
| `weapon_type` | number | Weapon type (see [Enumerations](#16-enumerations)). |
| `weapon_group` | string | Name of the active weapon config slot. |
| `can_fire` | boolean | The weapon can fire this tick. |
| `scoped` | boolean | You are scoped. |
| `profile` | table | Read-only active weapon profile. See below. |
| `speed` | number | Your horizontal speed. |
| `max_speed` | number | Weapon max speed (the scoped value while zoomed). |
| `fire_delay` | number | Seconds until the next attack. 0 when ready, -1 when unknown, out of ammo or frozen. |
| `friction` | number | `sv_friction` × surface friction. |
| `control_speed` | number | `sv_stopspeed`. |
| `interval` | number | Tick interval, in seconds. |
| `grounded` | boolean | You are on the ground. |
| `view_yaw`, `view_pitch` | number | Your real view angles. |
| `damage` | number | *Editable in `ragebot.target`, 1 to 200.* Minimum damage (the override value while the damage override key is held). |
| `body_aim` | boolean | *Editable in `ragebot.target`; only `true` is applied.* Force body aim. |
| `force_shoot` | boolean | *Editable in `ragebot.target`; only `true` is applied.* Force shoot. |

Each entry of `targets`:

| Field | Type | Meaning |
|---|---|---|
| `index` | number | Player index. |
| `health` | number | Health. |
| `fov` | number | FOV distance from your crosshair. |
| `missed_shots` | number | Missed shot counter. |
| `resolver_confidence` | number | Player-level resolver confidence. |
| `override` | number | Resolver override yaw, 0 when none is set. |
| `breaking_lc` | boolean | Breaking lag compensation. |
| `bearing_yaw`, `bearing_pitch` | number | Angles from your eye to the player's origin plus 48 units. |
| `records` | array | One or two record tables. |

Each target exposes at most two **records**: slot 1 is the record the native
scan would try first, and slot 2 is the oldest valid backtrack record.

| Field | Type | Meaning |
|---|---|---|
| `index` | number | Slot, 1 or 2. Pass it as the `record` argument. |
| `lag` | number | Choked ticks. |
| `grounded` | boolean | On the ground. |
| `broken` | boolean | Broke lag compensation. |
| `resolver_mode` | number | Internal resolver mode (see [Enumerations](#16-enumerations)). |
| `resolver_confidence` | number | 0 to 2. |
| `yaw` | number | Resolved eye yaw. |
| `body` | number | Lower body yaw. |
| `speed` | number | Horizontal speed. |
| `valid` | boolean | Valid for backtrack and not immune. |

`profile` fields: `hitchance`, `damage`, `prefer_hitchance`,
`prefer_overlap`, `assessed_damage`, `head_scale`, `body_scale`,
`head_misses`, `dynamic_scale` (boolean), `hitbox_mask`, `multipoint_mask`,
`autostop_mask`.

### `ragebot.stop`

Runs every tick before target choice, while not shooting manually. Both
`rage.scan` and `rage.knife_scan` work here. Candidates scanned here stay
valid for `ragebot.target` on the same tick.

Inputs: the shared context, plus `autostop` and `early_autostop` (booleans,
from the profile).

`original()` returns `{ autostop, early_autostop }` with the profile values.

| Result field | Type | Effect |
|---|---|---|
| `speed` | number, 0 to 450 | Slow down to this speed this tick. Native autostop is skipped. It only applies on the ground without jump: above the speed it counter-steers, and at or below it scales your movement input down. |
| `autostop` | boolean | Override the profile's autostop for this tick. |
| `early_autostop` | boolean | Override early autostop for this tick. |

### `ragebot.target`

Runs when the weapon is ready and a target must be chosen. Both `rage.scan`
and `rage.knife_scan` work here.

Inputs: the shared context, with `damage`, `body_aim` and `force_shoot`
editable (they apply through `original()`).

`original()` runs the native planner. If it found a target, it registers that
target as a candidate and returns
`{ candidate, target, damage, expected_damage, hitchance, hitbox }`. If not,
it returns `{ none = true }`.

| Result field | Type | Effect |
|---|---|---|
| `candidate` | number | Candidate id from `rage.scan` or `original()`. If the id is missing or invalid, no target is selected. |

A candidate a script picked (not the native one) skips native autostop and
delay shot. It still goes through `ragebot.shot` and `ragebot.fire`.

### `ragebot.shot`

Runs after a target is chosen, to set the shot style.

| Input | Type | Meaning |
|---|---|---|
| `target` | number | Player index, 0 if none. |
| `damage` | number | Predicted damage. |
| `hitbox` | number | Hitbox (see [Enumerations](#16-enumerations)). |
| `weapon_id`, `weapon_type` | number | Current weapon. |
| `silent`, `recoil`, `spread`, `draw_hitbox`, `revolver_secondary` | boolean | Current style. |

`original()` returns the five style booleans. Each result field is a boolean:
`silent` (silent aim), `recoil` (recoil compensation), `spread`,
`draw_hitbox` (draw the shot hitbox), `revolver_secondary` (fire the R8 with
attack2).

### `ragebot.fire`

Runs after hitchance is calculated.

| Input | Type | Meaning |
|---|---|---|
| `target`, `damage`, `hitbox`, `weapon_id`, `weapon_type` | | As in `ragebot.shot`. |
| `hitchance` | number | Calculated hitchance, from 0 to 100. |
| `required` | number | *Editable, 0 to 100.* Required hitchance. |
| `can_fire` | boolean | The weapon can fire. |
| `scoped` | boolean | You are scoped. |
| `scopeable` | boolean | The weapon can scope. |
| `force_shoot` | boolean | Force shoot is active. |
| `delay_shot` | boolean | The profile's delay shot flag. |
| `speed` | number | Your horizontal speed. |

`original()` returns `{ shoot, scope }`. `shoot` is `false` when the
hitchance is below the required value, or when delay shot holds the shot.

| Result field | Type | Effect |
|---|---|---|
| `shoot` | boolean | Fire this tick. |
| `scope` | boolean | Scope this tick. |

### `ragebot.knife`

Runs while holding a knife (not the Zeus).

Inputs: the shared context. `rage.knife_scan` works here.

`original()` runs the native knifebot and returns `{ native = true }`.

| Result field | Type | Effect |
|---|---|---|
| `target` | number, 1 to 64 | Player index. |
| `record` | number, 1 or 2 | Record slot. |

The attack is applied only when `can_fire` is true and the knife reaches that
record. The host picks stab or slash. Use `ctx.result = {}` to suppress the
native knifebot without attacking.

---

## 7. Resolver stages

### `resolver.resolve`

Runs for each new enemy record, after the native resolver.

| Input | Type | Meaning |
|---|---|---|
| `index` | number | Player index. |
| `generation` | number | Resolver generation; changes on reset or respawn. |
| `record_id` | number | Record identifier. |
| `sim_time`, `anim_time` | number | Simulation and animation time. |
| `interval` | number | Tick interval. |
| `body_yaw` | number | Lower body yaw. |
| `eye_yaw`, `eye_pitch` | number | Networked (unresolved) eye angles. |
| `speed` | number | Horizontal animation velocity. |
| `velocity_yaw` | number | Direction of velocity. |
| `grounded`, `fakewalk`, `shot` | boolean | Record flags. |
| `looks_real` | boolean | The native resolver kept the networked yaw. |
| `broken` | boolean | Broke lag compensation. |
| `overridable` | boolean | Script results are applied. False on shot records, records left unresolved, while a manual override is set, and on direct LBY updates. |
| `body_changed` | boolean | LBY changed by more than 0.1° since the previous record of this generation. |
| `adjust_activity`, `adjust_weight`, `adjust_cycle` | number | Adjust layer (3). Activity is -1 when there is no sequence. |
| `lag` | number | Choked ticks. |
| `away_yaw` | number | Yaw from the enemy towards you. |
| `origin_x`, `origin_y`, `origin_z` | number | Record origin. |
| `freestand_valid` | boolean | A cover side was found (standing on the ground only). |
| `freestand_yaw` | number | Cover yaw, or `away_yaw` when none. |
| `override_active` | boolean | A manual or script override is set. |
| `override_yaw` | number | Override yaw. |
| `direct_update` | boolean | This record is a directly observed LBY update. |
| `predicted_update` | boolean | This record is a predicted LBY update. |
| `confirmed_yaw` | number? | Standing only: a confirmed real yaw from flick memory. |
| `learned_yaw` | number? | Standing only: a learned flick yaw. |
| `body_trust` | number? | Standing only: trust in the body yaw. |
| `body_trusted` | boolean? | Standing only: the body yaw is trusted. |
| `motion_yaw` | number? | A motion-derived yaw, when available. |

`original()` returns `{ yaw, pitch, mode, hypothesis, confidence }` with the
native decision.

| Result field | Range | Effect |
|---|---|---|
| `yaw` | -180 to 180 | Resolved yaw. |
| `pitch` | -89 to 89 | Resolved pitch. |
| `mode` | integer 0 to 7 | Script mode (see [Enumerations](#16-enumerations)). It also sets the internal mode. |
| `hypothesis` | integer 0 to 32 | Hypothesis id attached to shots at this record. |
| `confidence` | integer 0 to 2 | 0 low, 1 medium, 2 high. |
| `candidates` | array, up to 6 | Alternative yaws: `{ yaw = -180..180, weight = (0, 1], hypothesis = 1..32 }`. If any entry is invalid, the whole list is dropped. |

Results are ignored unless `overridable` is true.

### `resolver.feedback`

Observe-only. Runs once per shot when its outcome is final, if the shot was
taken at a resolved record and the target is still the same life.

| Field | Type | Meaning |
|---|---|---|
| `index` | number | Player index. |
| `name` | string | Player name. |
| `generation`, `record_id` | number | Match these with `resolver.resolve`. |
| `shot_id` | number | Shot identifier. |
| `hypothesis`, `mode`, `confidence` | number | The resolver decision used for the shot. |
| `sim_time` | number | Record simulation time. |
| `yaw` | number | Yaw shot at. |
| `outcome` | string | `"hit"`, `"spread"`, `"occlusion"`, `"resolver_miss"` or `"unknown"`. |
| `reason` | string | A finer reason. For misses: `"spread"`, `"prediction_error"`, `"occlusion"`, `"lag_compensation"`, `"animations"`, `"fake_angles"` or `"unknown"`. `"hit"` for hits. |
| `hitgroup` | number | Hitgroup hit, 0 on a miss. |
| `aimed_hitbox` | number | Hitbox aimed at. |
| `predicted_damage` | number | Predicted damage. |
| `walls` | number? | Predicted walls penetrated. |
| `stopped_short` | number? | How far short the bullet stopped. |
| `wall_material` | string? | One-character surface material code. |
| `wall_thickness` | number? | Wall thickness. |
| `unknown_cause` | string? | For `unknown`: `"no_server_impact"`, `"not_registered"`, `"target_left"`, `"record_expired"`, `"target_dead"`, `"lag_compensation_no_records"` or `"no_resolver_mode"`. |
| `guess_count`, `guesses_ruled_out`, `consistent_guess_weight` | number? | Yaw-guess bookkeeping, when guesses existed. |
| `tracker_ruled_out` | boolean? | The tracker ruled the shot yaw out. |
| `tracker_confidence` | number? | Tracker confidence. |
| `lag`, `speed`, `feet_range`, `guesses` | number? | Record data, when the record still exists. |
| `fakewalk` | boolean? | Record was fake walking. |

---

## 8. Anti-aim stages

### Anti-aim snapshot

`antiaim.angles` and `antiaim.packet` receive this snapshot, built once per
command:

| Field | Type | Meaning |
|---|---|---|
| `mode` | string | `"air"`, `"duck"`, `"walk"` or `"stand"`. |
| `command_number` | number | Command number. |
| `session_id` | number | Increments on respawn, a new local player or time going backwards. |
| `time` | number | Current time. |
| `tick_interval` | number | Tick interval. |
| `speed` | number | Horizontal speed. |
| `move_delta` | number | Squared distance since the last sent position. |
| `lag`, `max_lag` | number | Choked commands so far, and the maximum allowed. |
| `view_yaw` | number | Your camera yaw. |
| `base_yaw` | number | Base yaw after `antiaim.view`. |
| `yaw`, `pitch` | number | The command's current angles. |
| `body_yaw` | number | Current LBY. |
| `body_update_time` | number | Next server LBY update time. |
| `enemy_body_update_time` | number | Next LBY update as an enemy would predict it. |
| `body_update` | boolean | LBY updates on this command. |
| `body_preupdate` | boolean | This is the tick before the LBY update. |
| `animation_valid` | boolean | Fields from the animation state below are valid. |
| `animation_time` | number | Last animation update time. |
| `feet_yaw` | number | Game animation-state feet yaw. |
| `ideal_pitch` | number | Minimum aim pitch from the animation state. |
| `abs_yaw` | number | Server-model real feet yaw. |
| `fake_feet_yaw` | number | Feet yaw an LBY-based resolver would see. |
| `feet_range` | number | Feet yaw width range. |
| `body_mismatches` | number | Count of LBY predictions that disagreed with the server. |
| `animation_rebuild` | boolean | The server animation rebuild is available. |
| `landing` | boolean | Airborne and predicted to land next tick. |
| `angles_allowed` | boolean | Angles can be changed on this command. |
| `safe_pitch` | boolean | Always `true`. |
| `lastmove_yaw` | number | Yaw recorded while last moving. |
| `manual_direction`, `manual_lastmove` | number | Manual directions (see [Enumerations](#16-enumerations)). |
| `lby_broken` | boolean | LBY timing is broken. |
| `packet` | boolean | Native send decision so far. |
| `old_packet` | boolean | Previous command's send decision. |
| `final_packet` | boolean | The final send state allowed. |
| `grounded`, `airborne`, `fresh_jump`, `ducking`, `freeze`, `fakewalk` | boolean | Movement state. |
| `pressing_move` | boolean | Movement keys are held. |
| `in_use` | boolean | Use key is held. |
| `shot`, `old_shot` | boolean | Shot on this or the previous command. |
| `has_target` | boolean | Anti-aim has a target. |
| `transition_flick` | boolean | Transition flick is active. |

### `antiaim.view`

Runs every command to choose the base view yaw that all anti-aim builds on.

| Input | Type | Meaning |
|---|---|---|
| `camera_yaw` | number | Camera yaw. |
| `native_yaw` | number | Base yaw the native code chose. |
| `at_targets` | boolean | The at-targets option is on. |
| `target` | number | Target player index, 0 if none. |
| `mode` | string | `"air"`, `"walk"` or `"stand"`. |

`original()` returns `{ yaw = native_yaw }`. Result: `yaw` (-3600 to 3600,
normalised).

### `antiaim.angles`

Runs every command. Hooking it disables the native anti-aim pipeline and the
native manual keys (while a script owns the manual direction). The
`rage.antiaim` building blocks work only inside this hook.

Inputs: the [snapshot](#anti-aim-snapshot).

`original()` runs the native pipeline, if the native anti-aim is enabled and
angles are allowed, and returns `{ pitch, yaw }`.

| Result field | Range | Effect |
|---|---|---|
| `pitch` | -89 to 89 | Command pitch. |
| `yaw` | -3600 to 3600 | Command yaw, normalised. |

The result is applied only while `angles_allowed` is true.

### `antiaim.breaker`

Runs when the standing LBY breaker runs.

| Input | Type | Meaning |
|---|---|---|
| `decoy` | number | *Editable, -3600 to 3600.* Decoy yaw. |
| `body_yaw` | number | LBY. |
| `feet_yaw` | number | Model feet yaw. |
| `body_update_time` | number | Next LBY update. |
| `time` | number | Current time. |
| `view_yaw` | number | Base yaw. |
| `preflicks` | number | Pre-flicks done this cycle. |
| `style` | number | Breaker style index from the menu. |
| `gap` | number | Decoy gap from the menu. |

`original()` runs the native breaker and returns `{ yaw, hide, decoy }`.

| Result field | Range | Effect |
|---|---|---|
| `yaw` | -3600 to 3600 | Command yaw. |
| `hide` | 0 to 2 | Hide mode (see `rage.antiaim.hide`). |
| `decoy` | -3600 to 3600 | Decoy yaw to keep for the next cycle. |

### `antiaim.twist`

Runs when the moving twist runs.

| Input | Type | Meaning |
|---|---|---|
| `feet_yaw`, `fake_feet_yaw` | number | Real and observed feet yaw. |
| `gap` | number | Absolute difference between the two. |
| `width` | number | Feet yaw width range. |
| `target_yaw` | number | Twist target. |
| `yaw` | number | Current command yaw. |
| `speed` | number | Horizontal speed. |
| `mode` | string | `"air"`, `"walk"` or `"stand"`. |

`original()` runs the native twist and returns `{ yaw, choke }`. Results:
`yaw` (-3600 to 3600) and `choke` (0 to 3, the number of twist ticks to
choke).

### `antiaim.packet`

Runs every command to choose whether to send or choke.

Inputs: the [snapshot](#anti-aim-snapshot). `packet` holds the native
decision.

`original()` returns `{ send = packet, fakewalk_sync = false }`.

| Result field | Type | Effect |
|---|---|---|
| `send` | boolean | Send (`true`) or choke (`false`). |
| `fakewalk_sync` | boolean | Ask fake walk to synchronise with this choke cycle. |

Native safety still forces a send at the maximum choke, on a fresh jump and
on shots.

### `antiaim.enemy_shot`

Observe-only. Runs when an enemy's shot at you is finalised: you were hit, or
the bullet impact passed within 64 units of your head.

| Field | Type | Meaning |
|---|---|---|
| `index` | number | Attacker index. |
| `name` | string | Attacker name. |
| `hit` | boolean | You were hit. |
| `hitgroup` | number | Hitgroup hit. |
| `damage` | number | Health damage taken. |
| `distance` | number | Closest impact distance to your head, -1 when there was no impact. |
| `state` | string | `"script"`, `"standing (no breaker)"`, `"standing (breaker)"`, `"moving (twist)"`, `"moving (no twist)"`, `"fakewalk"`, `"air"` or `"anti-aim off"`. |
| `desync` | number | Absolute difference between real and observed feet yaw. |
| `real_yaw`, `fake_yaw` | number | Real and observed feet yaw relative to the attacker's direction. |
| `speed` | number | Your speed. |

---

## 9. `rage`

### `rage.scan(target, record, options) -> candidate?`

Runs a native scan of one record with your options. Only works inside
`ragebot.stop`, `ragebot.target` and `ragebot.knife`. Returns `nil` outside
them, on any invalid argument, when nothing passes, or after 2048 candidates
in one tick.

- `target`: a player index, or a target table (its `index` field is read).
- `record`: a slot (1 or 2), or a record table.
- `options`: a table. **Every field is required.**

| Option | Range | Meaning |
|---|---|---|
| `hitboxes` | integer 1 to 31 | Hitbox group mask: 1 head, 2 chest, 4 stomach, 8 arms, 16 legs. |
| `body_mode` | integer 0 to 3 | 0 none, 1 body only, 2 prefer body when lethal, 3 prefer body when two shots are lethal. |
| `multipoint` | integer 0 to 15 | Multipoint mask: 1 head, 2 chest, 4 stomach, 8 legs. |
| `damage` | 1 to 200 | Minimum visible damage. |
| `penetration_damage` | 1 to 200 | Minimum damage through walls. |
| `scale` | 0 to 1 | Point scale. |
| `body_scale` | 0 to 1 | Body point scale. |
| `penetration` | boolean | Allow wall penetration. |

The returned candidate:

| Field | Meaning |
|---|---|
| `id` | Pass it as `ctx.result = { candidate = id }` in `ragebot.target`. |
| `damage` | Damage. |
| `expected_damage` | Damage weighted by the yaw guesses. |
| `hitchance` | Point hitchance, from 0 to 100. |
| `simulated_angle` | Guess index used, or -1. |
| `hypothesis` | Resolver hypothesis for that guess. |
| `health` | Target health. |
| `fov` | FOV to the point. |
| `distance` | Distance to the record. |
| `height` | Record height relative to you. |
| `lag` | Choked ticks. |

### `rage.knife_scan(target, record) -> boolean`

Returns `true` when a knife attack reaches that record. Same arguments as
`rage.scan`. Works only inside the ragebot hooks while holding a knife (not the
Zeus).

### `rage.resolver.override(target, yaw?)`

Pins a target's resolved yaw (-180 to 180). Omit `yaw`, or pass `nil`, to
clear your override. `target` is an index or a target table.

The override is owned by the calling script. A script can only clear its own.
Clearing it, or unloading the script, restores the value that was there
before, unless the built-in override key changed it in the meantime. Resolve
events report it as `override_active` and `override_yaw`.

---

## 10. `rage.antiaim`

### Building blocks

These run only inside an `antiaim.angles` hook. Called anywhere else, they
raise an error. Unless noted, each one applies its step only while angles are
allowed, then returns the command's current `pitch, yaw`.

| Function | Effect |
|---|---|
| `run()` | Runs the complete native anti-aim pipeline. |
| `twist()` | Applies the native move twist. |
| `flick()` | Applies the native flick. |
| `suppress()` | Limits the yaw so the feet do not snap. |
| `freestand() -> yaw` | Returns the dynamic freestand pick among base+180, base+90 and base-90. Does not change the command. |
| `manual() -> yaw, direction` or `nil` | Returns the yaw for the current manual direction and its number, or `nil` when none is set. |
| `hide(mode)` | Sets the hide mode: 0, 1 or 2. 0 records this command's yaw as your real angle; 1 and 2 hide it (2 is used for flick-stage packets). Accepts dot or colon. |

### Queries

| Function | Where | Returns |
|---|---|---|
| `get_target("fov" \| "distance")` | anywhere during command processing | Yaw from you to the closest enemy by FOV or distance, or `nil`. Accepts dot or colon. |
| `get_freestanding("fov" \| "distance")` | anywhere during command processing | Cover yaw against that enemy, or `nil`. Cached per command. It measures world cover, not incoming damage. Accepts dot or colon. |
| `edge()` | anywhere during command processing | `yaw, distance` to the closest wall within 40 units at head height (16 directions), or `nil`. |
| `predict(yaw, pitch?)` | inside `antiaim.angles` or `antiaim.packet` | Read-only `{ feet_yaw, feet_range, body_yaw, body_update }`, or `nil`. Animates a copy of your state with those angles without changing anything. `pitch` defaults to the command pitch and must be within ±89. At most 8 calls per command. Accepts dot or colon. |

### Setters

All setters accept dot or colon.

| Function | Effect |
|---|---|
| `set_manual(direction?, lastmove?) -> boolean` | Sets the manual direction: `"back"`, `"left"`, `"right"`, `"forward"`, or `nil` to clear. `lastmove` takes the same values. The native pipeline, the manual arrows indicator and the keybind list read it. The value is owned by the calling script and restored on clear or unload, as with resolver overrides. Returns `false` on invalid arguments. |
| `set_twist_movement(delay_move, crank) -> boolean` | Enables the movement-side twist options that a script cannot do itself: delay move and crank. Reset on unload. |
| `set_lastmove_repeat(enabled?)` | Whether the last-move side repeats. `nil` means `true`. Reset on unload. |

---

## 11. `ui`

### `ui.create(tab, group, column?, pages?, persistent?) -> group?`

Creates a control group owned by your script.

| Argument | Meaning |
|---|---|
| `tab` | `"Ragebot"`, `"Anti-Aim"` (or `"anti-aim"`), `"Nades"` (or `"nades"`), `"Misc"` (or `"misc"`). |
| `group` | Group name. It forms part of each control's persistence key. |
| `column` | 1 (default) or 2. |
| `pages` | Ragebot only: a page name or a list of names. Script controls live on the tab's **script** page, listed while any script has a group there. Named pages are added to that page's selector and removed when no group uses them; groups without pages show on the script page whatever is selected. Passing pages for any other tab returns `nil`. Anti-Aim groups always go on that tab's **script** page. |
| `persistent` | Default `true`. `false` creates controls whose values are never saved. |

Returns `nil` on invalid arguments or during teardown.

### Group methods

Each method returns a control, or `nil` on invalid arguments. Creating a
control with the same group and label again returns the existing control.

| Method | Arguments |
|---|---|
| `group:switch(label, default?)` | `default` is a boolean, `false` if omitted. |
| `group:slider(label, min, max, initial)` | All required and finite, with `min < max`. `initial` is clamped. |
| `group:combo(label, choices)` | A non-empty array of strings. |
| `group:multi_combo(label, choices)` | 1 to 32 strings. |
| `group:hotkey(label, key?)` | Virtual key code from -1 to 255, default -1 (unbound). A label containing "manual" is locked to hold mode and left out of the keybind list. |
| `group:button(label)` | Clicks are delivered as `events.ui` with `kind = "click"`. Never saved. |

### Control methods

| Method | Applies to | Effect |
|---|---|---|
| `:get()` | all | Switch: boolean. Slider: number. Combo: one-based index. Multi-combo: bitmask (bit 0 is the first choice). Hotkey: key code. Button: `nil`. |
| `:set(value)` | all except button | Same types as `get`. Invalid values are ignored. Saves persistent controls. |
| `:active()` | hotkey | The bound key is currently active. |
| `:pressed()` | hotkey | `true` once per press since the last call. |
| `:mode()` | hotkey | `"hold"` or `"toggle"`. Raises an error on other controls. |
| `:set_mode(mode)` | hotkey | `"hold"` or `"toggle"`. Raises an error otherwise. |
| `:show_if(selector, value)` | all | Show only while `selector` (your own combo or switch) has `value`: a one-based combo index, or for a switch 1 = off and 2 = on. Conditions add up, and all must hold. |
| `:show_if_any(selector, values)` | all | The same, with a list of accepted values. |
| `:set_label(text)` | all | Changes the displayed label only. The persistence key keeps the original label. |
| `:set_choice_label(index, text)` | combo | Renames an existing choice (one-based). Raises an error on an invalid index. |
| `:per_weapon()` | saved Ragebot controls except buttons | Gives the control one value per aimbot weapon slot, like the native weapon config: the menu shows the slot the weapon selector is on, editing a weapon slot turns on that slot's override, turning the override off returns the slot to the global value, and `:get()` returns the value for the weapon you hold (the global value when it has no override). Returns the control. Raises an error on other controls. |
| `:set_tooltip(text)` | all | Hover text for the control, shown after a second. `""` removes it. |
| `:set_choice_tooltip(index, text)` | combo, multi-combo | Hover text for one choice (one-based), shown while the list is open. Raises an error on an invalid index. |

Controls also carry a read-only `__handle` number, which matches
`events.ui` `handle`.

### Reading, writing and placing controls

```lua
ui.get(tab, id)                          --> value | nil
ui.set(tab, id, value)                   --> boolean
ui.set(tab, page, column, kind, label, ...) --> control | nil
```

`ui.get` reads a **built-in** setting by its config id (see `ui.elements`), with
the types `control:get()` uses: switch boolean, slider number, combo one-based
index, multi-combo bitmask, hotkey key code. Colors return `r, g, b, a`. It
returns `nil` when the id is not on that tab.

`ui.set(tab, id, value)` writes a built-in setting with the same types (colors
take `r, g, b, a?`) and returns whether it applied. Invalid values are ignored.
Aimbot settings that are part of the weapon profile write into the profile the
menu is editing, which is the held weapon's slot while you are in game: writing
one there gives that weapon its own override, as editing it by hand would.

`ui.set(tab, page, column, kind, label, ...)` makes a control and returns it,
like the group methods. `page` is a built-in page name (`"aim"`, `"trigger"` on the
Ragebot tab, where the old name `"fire"` also means `"trigger"` and values saved under it move to `"trigger"`; `"real"`, `"fake"`, `"twist"`, `"lag"` on the Anti-Aim tab), where
the control goes below that page's own controls in `column` (1 or 2), or `nil` /
`"script"` for the tab's script page. `kind` is `"switch"`, `"slider"`,
`"combo"`, `"multi_combo"`, `"hotkey"` or `"button"`, and the arguments after
`label` are the ones that group method takes. Controls made this way belong to
an internal group named after the page, so a value is saved under that page name
and the label. Calling it again with the same page, column and label returns
the existing control.

### Saved values

```lua
ui.saved_value(group, label) --> boolean | number | string | nil
ui.discard_saved_value(group, label)
```

These read or delete a persisted value without a live control, for example to
migrate an old label. The lookup uses the Ragebot persistence key, so it
reaches controls on the Ragebot, Nades and Misc tabs, but not the Anti-Aim
tab.

### Hiding menu elements

```lua
ui.hide(control, hidden?)          --> boolean
ui.hide(tab, hidden?)              --> boolean
ui.hide(tab, element_id, hidden?)  --> boolean
ui.elements(tab)                   --> { { id, label, hidden } }
```

`hidden` defaults to `true`; pass `false` to show again. `ui.hide` returns
whether anything matched.

- The `control` form hides one of your own controls. This combines with its
  `show_if` conditions.
- The tab forms hide **built-in** elements: all of them, or the one whose
  config id is `element_id`. Script controls are never matched, so you can
  hide the built-in UI and keep your own. The Anti-Aim page bar is never
  hidden.
- Hiding is visual only. Hidden built-in settings and keybinds keep working.
- Built-in hides belong to your script and are undone when it unloads. An
  element hidden by several scripts stays hidden until all of them release it.

`ui.elements(tab)` lists the built-in elements that have a config id.

### Persistence

Persistent values are saved to `<stem>.current.cfg`. Each key is the tab id
(`anti-aim` for the Anti-Aim tab, `aimbot` for the others), the group and the
original label, separated by `\u001f`. Values autosave 500 ms after the last
change, and are written immediately on unload. Values are loaded before the
script runs, so a new control starts at its saved value.

Because the Ragebot, Nades and Misc tabs share the `aimbot` key, a group and
label used on two of those tabs refer to the same control.

---

## 12. `settings`

Structured data, saved per script.

### `settings.open(namespace, defaults, max_schema_version?) -> handle`

| Argument | Meaning |
|---|---|
| `namespace` | 1 to 128 characters from `A-Z a-z 0-9 _ - .`. |
| `defaults` | A table, stored the first time the namespace is opened. |
| `max_schema_version` | Optional non-negative integer. When given, a top-level `version` field above it, either in the defaults or in the stored data, raises an error. It cannot change while the namespace is open. |

Opening the same namespace again returns a handle to the same binding.
Raises an error on an invalid namespace, invalid data or during teardown.

| Method | Effect |
|---|---|
| `:get()` | Returns a detached deep copy. |
| `:set(table)` | Validates and commits the whole value atomically, saves it, increments the revision and queues `events.settings`. Raises an error and changes nothing on invalid data or during teardown. |
| `:revision()` | A number that increases on every commit. |

**Allowed values:** booleans, finite numbers, strings, and tables with only
string keys and no metatable. Arrays, `nil` values, functions, userdata and
cycles are rejected. Limits are a depth of 32, 16,384 nodes and 1 MiB of JSON.

Data is saved to `<stem>.dat` (one JSON object keyed by namespace). It
survives reloads. A failed load rolls it back to the state before the load.

---

## 13. `indicators`

The status indicator list (bottom-left: LC, LBY, PING).

### `indicators.add(name, text?) -> handle?`

Creates a custom indicator. `name` and `text` are 1 to 32 bytes, and `text`
defaults to `name`. Adding a name you already own returns the same handle.
Built-in names (`lc`, `lby`, `ping`) and names owned by other scripts return
`nil`.

| Method | Effect |
|---|---|
| `:set_text(text)` | 1 to 32 bytes. |
| `:set_enabled(boolean)` | Whether your script wants it drawn. |
| `:set_active(boolean)` | Green (active) or red (inactive) state colour. |
| `:set_color(r, g, b, a?)` | Custom colour, channels 0 to 255, `a` defaults to 255. Call with no arguments to go back to the state colour. |
| `:remove()` | Removes it. |

Each custom indicator also appears under **Visuals > indicators**, selected by
default. The choice is remembered across reloads for the session. It is drawn
only when that menu entry is selected, the script has it enabled, and you are
alive in game. Unloading the script removes it.

### `indicators.get(name)` and `indicators.list()`

`get` returns a read-only state table, or `nil`. `list` returns every state in
draw order: built-ins first, then custom indicators in creation order. State
fields:

| Field | Meaning |
|---|---|
| `name`, `text` | Strings. |
| `owner` | Owning script, empty for built-ins. |
| `builtin` | Boolean. |
| `enabled` | Enabled by its owner. |
| `selected` | Selected in the menu. |
| `visible` | Drawn this frame. |
| `active` | Green or red state. |
| `r`, `g`, `b`, `a` | Draw colour. |

States refresh every HUD paint frame.

---

## 14. `client`

| Function | Returns | Notes |
|---|---|---|
| `client.chat_print(text)` | boolean | Prints a local chat line (not sent to the server). 1 to 240 bytes, in game only. Accepts dot or colon. |
| `client.set_name(name)` | boolean | Sets your `name` convar. 1 to 127 bytes, no embedded NULs. Accepts dot or colon. |
| `client.get_name()` | string | Current `name` convar. |
| `client.in_game()` | boolean | The engine is in game. |
| `client.alive()` | boolean | The local player is alive. |
| `client.realtime()` | number | Engine real time, in seconds. |

---

## 15. `sound`

| Function | Returns | Notes |
|---|---|---|
| `sound.play(sample, volume?)` | boolean | Plays a client-side sound. `sample` is a preset name or a game sound path: `.wav` or `.mp3`, at most 128 characters, only letters, digits and `_ - / .`, no `..` and no leading slash. `volume` is clamped to 0 to 1 (default 1) and scaled by the game's master volume. Returns whether the sound was submitted. |
| `sound.presets()` | `{ string }` | The hitsound preset names: `default`, `bell`, `blip`, `click`, `bleep`, `headshot`, `metal`. |

---

## 16. Enumerations

### Weapon type (`weapon_type`)

| Value | Type |
|---|---|
| 0 | knife |
| 1 | pistol |
| 2 | SMG |
| 3 | rifle |
| 4 | shotgun |
| 5 | sniper rifle |
| 6 | machine gun |
| 7 | C4 |
| 8 | taser |
| 9 | grenade |
| 11 | healthshot |

### Hitbox (`hitbox`, `aimed_hitbox`)

| Value | Hitbox | Value | Hitbox |
|---|---|---|---|
| 0 | head | 10 | right calf |
| 1 | neck | 11 | left calf |
| 2 | lower neck | 12 | right foot |
| 3 | pelvis | 13 | left foot |
| 4 | body (stomach) | 14 | right hand |
| 5 | thorax | 15 | left hand |
| 6 | chest | 16 | right upper arm |
| 7 | upper chest | 17 | right forearm |
| 8 | right thigh | 18 | left upper arm |
| 9 | left thigh | 19 | left forearm |

### Hitgroup (`hitgroup`)

| Value | Hitgroup |
|---|---|
| 0 | generic |
| 1 | head |
| 2 | chest |
| 3 | stomach |
| 4 | left arm |
| 5 | right arm |
| 6 | left leg |
| 7 | right leg |
| 8 | neck |
| 10 | gear |

### Resolver script mode (`resolver.resolve` `mode`, feedback `mode`)

| Value | Meaning |
|---|---|
| 0 | none: the networked yaw looks real |
| 1 | moving |
| 2, 3, 4 | standing (three values reserved for script sub-modes) |
| 5 | in air |
| 6 | LBY update, observed |
| 7 | LBY update, predicted (weak evidence) |

### Internal resolver mode (record `resolver_mode`, `animation` `mode`)

| Value | Meaning |
|---|---|
| 0 | air |
| 1 | stand |
| 2 | LBY update |
| 3 | move |
| 4 | none |

### Manual direction (`manual_direction`, `manual_lastmove`, `manual()`)

| Value | Direction |
|---|---|
| -1 | none |
| 0 | back |
| 1 | right |
| 2 | left |
| 3 | forward |

---

## 17. Files on disk

All files live in `Documents\Divinity\Scripts`. `<stem>` is the script
filename without `.lua` or `.luau`.

| File | Contents |
|---|---|
| `loaded_scripts.cfg` | `{"version":1,"scripts":["ragebot.luau", ...]}`: the enabled scripts. |
| `<stem>.current.cfg` | JSON with the persistent UI values. Buttons and non-persistent controls are not saved. |
| `<stem>.dat` | JSON with the `settings` namespaces. |
| `api.d.luau` | Type declarations for analysis. Never loaded. |

Writes are atomic: a temporary file is written, then swapped in. A file that
is malformed, unreadable or too large is reported and is never overwritten;
repair or delete it, then reload. Unknown keys survive saves. Native `.div`
presets do not contain script state.

---

## 18. Examples

### Tweak minimum damage and report the native pick

```lua
hooks.set("ragebot.target", function(ctx)
    ctx.damage = 30
    local native = ctx:original()
    if native and native.candidate then
        print("native picked", native.target, native.damage)
    end
end)
```

### Pick your own target with `rage.scan`

```lua
local options = {
    hitboxes = 1 + 2 + 4, body_mode = 2, multipoint = 1 + 2,
    damage = 20, penetration_damage = 20,
    scale = 0.7, body_scale = 0.6, penetration = true,
}

hooks.set("ragebot.target", function(ctx)
    local best
    for index, target in pairs(ctx.targets) do
        for _, record in ipairs(target.records) do
            local candidate = rage.scan(index, record.index, options)
            if candidate and (not best or candidate.expected_damage > best.expected_damage) then
                best = candidate
            end
        end
    end
    ctx.result = best and { candidate = best.id } or {}
end)
```

### Require more hitchance while moving

```lua
hooks.set("ragebot.fire", function(ctx)
    if ctx.speed > 5 then
        ctx.required = math.min(100, ctx.required + 15)
    end
    ctx:original()
end)
```

### Jitter on top of the native anti-aim

```lua
local group = ui.create("Anti-Aim", "Jitter", 2)
local enabled = group:switch("Enable jitter")
local range = group:slider("Range", 0, 90, 30)
range:show_if(enabled, 2)

hooks.set("antiaim.angles", function(ctx)
    local pitch, yaw = rage.antiaim.run()
    if enabled:get() then
        local side = ctx.command_number % 2 == 0 and 1 or -1
        ctx.result = { pitch = pitch, yaw = yaw + side * range:get() }
    end
end)
```

### Persist structured data and clean up

```lua
local store = settings.open("stats", { version = 1, kills = 0 }, 1)

events.ui:set(function(event)
    if event.kind == "click" then
        local data = store:get()
        data.kills = 0
        store:set(data)
    end
end)

events.shutdown:set(function(event)
    print("shutting down:", event.reason)
end)
```

### Custom indicator and hitsound

```lua
local key = ui.create("Ragebot", "Extras"):hotkey("Ping spike")
local label = indicators.add("spike", "SPIKE")

events.tick:set(function()
    if label then
        label:set_enabled(key:active())
    end
    if key:pressed() then
        sound.play("bell", 0.5)
    end
end)
```
