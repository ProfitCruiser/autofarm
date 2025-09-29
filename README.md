# autofarm

Server-side Kriluni auto-farming scripts for Roblox experiences.

## Contents

- `ServerScriptService/KriluniAutoFarm.lua`: Main server Script handling scanning, targeting, pathing updates, DPS ticks, and reward payouts. Includes configurable target folders/name filters and shares attack range with clients for navigation.
- `ServerScriptService/CombatAdapter.lua`: Adapter allowing damage delivery via direct Humanoid damage or a remote combat API.
- `ServerScriptService/CurrencyAdapter.lua`: Utility module to safely award currency in common player data layouts.
- `autofarm.lua`: Client-side UI and feature implementation (existing).

## Setup

1. Place the contents of `ServerScriptService` into your Roblox game's **ServerScriptService**.
2. Ensure the `autofarm.lua` client script is injected/executed from the client (e.g. via a LocalScript or executor).
3. Customize the `CONFIG` table inside `KriluniAutoFarm.lua` to match your game's folder names, reward key, damage mode, and DPS settings. You can list target folders via `TARGET_FOLDERS`, exact name matches via `TARGET_MODEL_NAMES`, or keywords/NPCId filters to lock onto specific mobs.
4. The server will automatically spawn `AutoFarmRequest` and `AutoFarmUpdate` RemoteEvents under `ReplicatedStorage/Remotes` for client communication.
5. On the client, open the **Kriluni Farm** tab in `autofarm.lua` and use the Start/Stop control to toggle the server-driven farm loop. The client now follows the server-provided navigation points automatically until within attack range.
