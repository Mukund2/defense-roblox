# Military Base Tycoon — Dev Guide

## How to Push Code Changes to Studio

**DO NOT use Rojo.** Use the Official Roblox Studio MCP directly:

1. **Edit files** on disk in `src/` using Write/Edit tools
2. **Push to Studio** using `multi_edit` (stop play mode first):
   ```
   mcp__Roblox_Studio_Official__multi_edit
   file_path: "game.ServerScriptService.ScriptName"
   edits: [{"old_string": "...", "new_string": "..."}]
   ```
   For new scripts, add `className: "Script"` (or `"ModuleScript"`, `"LocalScript"`)
3. **Play and verify** using `start_stop_play` + `screen_capture`
4. **Commit to git** after verifying

### Script Locations in Studio
| Disk Path | Studio Path |
|-----------|-------------|
| `src/server/Name.server.luau` | `game.ServerScriptService.Name` (Script) |
| `src/server/Name.luau` | `game.ServerScriptService.Name` (ModuleScript) |
| `src/shared/Name.luau` | `game.ReplicatedStorage.Name` (ModuleScript) |
| `src/client/Name.client.luau` | `game.StarterPlayer.StarterPlayerScripts.Name` (LocalScript) |
| `src/StarterGui/Name/init.client.luau` | `game.StarterGui.Name` (LocalScript) |

### Important Notes
- **Always enable HTTP** before any HTTP operations: `game:GetService("HttpService").HttpEnabled = true`
- **Stop play mode** before using `multi_edit` — it can't edit during play
- **Old save data** persists in Studio DataStore. To reset: File > Studio Settings > Security > turn OFF "Enable Studio Access to API Services"
- **multi_edit can create scripts** by setting `className` parameter — useful when scripts are missing

## Project Structure

```
src/
├── server/          → ServerScriptService
│   ├── TycoonManager.server.luau    (main orchestrator)
│   ├── TycoonBuilder.luau           (world/building construction)
│   ├── DataManager.luau             (save/load player data)
│   ├── IncomeManager.luau           (income tick loop)
│   ├── BuildingBehaviors.luau       (dropper animations per building)
│   ├── WeaponManager.luau           (gives weapons on building unlock)
│   ├── VehicleManager.luau          (spawns drivable vehicles)
│   ├── CombatManager.server.luau    (base attack system)
│   ├── DamageHandler.server.luau    (FPS hit validation)
│   ├── RemoteBoot.server.luau       (creates RemoteEvents early)
│   ├── LeaderboardManager.luau
│   ├── DailyRewardManager.luau
│   ├── QuestManager.luau
│   ├── UnitManager.luau             (disabled — placeholder units)
│   ├── UnitBehaviors.luau
│   └── EffectsManager.luau
├── shared/          → ReplicatedStorage
│   ├── Remotes.luau                 (all RemoteEvents/Functions)
│   ├── TycoonConfig.luau            (building definitions, costs)
│   ├── CombatConfig.luau            (attack types, defense stats)
│   ├── UnitConfig.luau
│   └── FormatNumber.luau
├── client/          → StarterPlayerScripts
│   ├── GunController.client.luau    (FPS shooting, multi-weapon)
│   ├── VehicleController.client.luau (vehicle HUD, driving)
│   ├── TycoonClient.client.luau     (purchase button touch)
│   ├── CameraEffects.client.luau
│   ├── SoundManager.client.luau
│   ├── CombatEffects.client.luau
│   └── Tutorial.client.luau
└── StarterGui/      → StarterGui
    ├── TycoonHUD/       (money, income, level display)
    ├── ShopGUI/         (building shop overlay, B key)
    ├── CombatHUD/       (HP bar, attack panel, F key)
    ├── QuestGUI/        (daily quests)
    ├── DailyRewardGUI/  (streak rewards)
    └── KillFeedGUI/     (kill notifications)
```

## Game Systems

### Tycoon Flow
1. Player spawns at center, walks to green claim pad at a compass point
2. Touch claim pad → creates base platform + cash collector
3. Purchase buttons appear one at a time (linear progression)
4. Step on button → buy building → building drops in with animation
5. Each building adds income/sec, income accumulates in cash collector
6. Walk on cash collector to collect pending cash

### Buildings (15 tiers)
CommandCenter ($100) → Barracks ($500) → MotorPool ($1.5K) → RadarStation ($3K) → SAMSite ($5K) → Helipad ($10K) → Armory ($15K) → TankDepot ($25K) → DroneHangar ($40K) → FighterJetHangar ($75K) → SubmarinePen ($120K) → AircraftCarrierDock ($200K) → StealthBomberBay ($350K) → NuclearSilo ($500K) → SpaceCommand ($1M)

### Vehicles (unlocked by buildings)
| Vehicle | Building | Type | Weapon |
|---------|----------|------|--------|
| Humvee | MotorPool | Ground | None |
| Helicopter | Helipad | Aircraft | Missiles |
| Tank | TankDepot | Ground | Shells |
| Drone | DroneHangar | Aircraft | Projectiles |
| Fighter Jet | FighterJetHangar | Aircraft | Missiles |

### Weapons (unlocked by buildings)
| Weapon | Building | Damage | Fire Rate |
|--------|----------|--------|-----------|
| Military Rifle | Default | 15 | 0.15s |
| Sniper Rifle | SAMSite | 65 | 1.2s |
| Shotgun | Armory | 45 | 0.6s |
| RPG | DroneHangar | 100 | 2.5s |

### Combat
- FPS: equip weapon, click to shoot, server validates hits
- Base attacks: F key → attack panel, choose attack type, target enemy pad
- Attacks require specific buildings and cost cash
- Bases have HP + shields, shields regen after 10s

### New Player Defaults
- Starting cash: $500
- Income: $0/sec
- Buildings: none (must buy everything)
- Walk speed: 32
