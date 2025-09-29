# autofarm

Executor-side Kriluni auto-farm script for Roblox experiences that exposes a full Aurora panel UI. The farm logic runs entirely on the client/executor without requiring any custom server remotes.

## Contents

- `autofarm.lua`: Main executor script. Builds the UI, handles key gating, and bundles the Kriluni farming logic alongside aimbot/ESP utilities.

## Getting Started

1. Join the experience and execute `autofarm.lua` through your executor after the world loads.
2. Complete the Aurora key prompt to unlock the panel.
3. Open the **Kriluni Farm** tab and press **Start** to toggle the farm loop on/off.

## Kriluni farm behaviour

- Continuously scans the workspace for models whose name includes `Kriluni` or expose `NPCId="Kriluni"`.
- Uses `Humanoid:MoveTo` commands to walk toward the nearest alive target while showing live distance updates in the UI.
- When inside the configured attack range, fires one of the existing combat remotes (Damage_Event/Player_Damage/To_Server/API). The script automatically tests several payload styles and caches the first working one. If no remote succeeds it falls back to `Humanoid:TakeDamage` for compatibility with custom setups.
- Keeps attacking until the target dies, then immediately searches for the next Kriluni.

## Configuration

Tune the `FARM_CONFIG` table near the top of `autofarm.lua`:

- `AttackRange`, `ScanInterval`, `AttackCooldown`, `DamagePerHit`: control spacing, polling, and DPS pacing.
- `TargetKeywords` / `TargetNPCIds`: adjust which mobs qualify as Kriluni targets.
- `Combat.RemotePaths`: ordered list of remote locations to try (each entry is a table path such as `{"ReplicatedStorage","Events","Damage_Event"}`).
- `Combat.PayloadStyles`: payload formats to attempt for each remote (`TargetOnly`, `TargetDamage`, `VerbTargetDamage`, `VerbTable`, `Table`).

Update the list to match the live experience if additional remotes or folders must be used.

## Notes

- The farm runs completely client-side. Rewards are granted by the experience's existing combat handlers once the remote accepts the attack.
- Movement and combat occur through normal Roblox APIs, so keep the executor running while farming.
- The script retains the rest of the Aurora utilities (aimbot, ESP, visuals) from earlier revisions.
