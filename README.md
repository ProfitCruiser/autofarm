# autofarm

Executor-side Kriluni auto-farm script for Roblox experiences that still use the Aurora key prompt but removes every extra panel
(Aimbot, ESP, etc.). The only UI after the key gate is the dedicated Kriluni farm controller.

## Contents

- `autofarm.lua`: Main executor script. Presents the key gate, then spawns a compact Kriluni farm panel with Start/Stop control and
  live status feedback.

## Getting Started

1. Join the experience and execute `autofarm.lua` through your executor once the world finishes loading.
2. Complete the Aurora key prompt to unlock the panel. The **Get Key** button copies the URL used for key retrieval.
3. Press **Start** on the Kriluni Farm panel to begin automatic target acquisition, navigation, and damage.

## Kriluni farm behaviour

- Continuously scans the workspace for alive models whose name contains `Kriluni` or expose `NPCId = "Kriluni"`.
- Commands the local Humanoid to walk to the closest target, with basic stuck detection and UI distance updates.
- Once within the configured attack range, tries the listed combat remotes (Damage_Event/Player_Damage/To_Server/API) using several
  payload styles, falling back to `Humanoid:TakeDamage` if every remote rejects the call.
- Repeats the process immediately after a kill so the farm never idles while Kriluni enemies exist.

## Configuration

Adjust the `FARM_CONFIG` table near the top of `autofarm.lua`:

- `AttackRange`, `ScanInterval`, `AttackCooldown`, `DamagePerHit`, `MaxAcquireDistance`: tune spacing, polling cadence, and DPS.
- `TargetKeywords` / `TargetNPCIds`: control which mobs qualify as Kriluni.
- `Combat.RemotePaths`: ordered list of RemoteEvents to try (each entry is a table path such as `{"ReplicatedStorage","Events","Damage_Event"}`).
- `Combat.PayloadStyles`: payload formats to attempt for each remote (`TargetOnly`, `TargetDamage`, `VerbTargetDamage`, `VerbTable`, `Table`).

## Notes

- All logic runs client-side; rewards come from the experience once combat remotes succeed.
- Keep the executor open so movement and damage commands continue to fire.
- The UI no longer exposes any ESP, aimbot, or extra Aurora utilities—only the key system and farm toggle remain.
