# BFM mission setup

`BFM.lua` adds a **BFM** F10 radio menu for every occupied BLUE airplane group.
It is standalone: no MIST, MOOSE, template aircraft, or trigger zones are required.

1. In the Mission Editor, assign **Combined Joint Task Forces Red** to RED.
2. Add your BLUE Player/Client airplane slots.
3. Add a **MISSION START** trigger with **DO SCRIPT FILE**, selecting `BFM.lua`.
4. Add a subsequent **DO SCRIPT** action: `BFM.init()`.

Menus appear within five seconds of joining a slot, including late joins. Load the
file only once; repeated `BFM.init()` calls are harmless and keep the original settings.

## Radio menu

Choose **F10 Other → BFM → MiG-29S / MiG-21bis**, then:

| Setup | Opponent's starting position | Opponent's heading |
| --- | --- | --- |
| Neutral | 2 NM ahead | Toward you |
| Offensive | 0.7 NM ahead | Same as you; you start behind it |
| Defensive | 0.7 NM behind | Same as you; it starts behind you |

Each selection spawns one armed AI opponent with guns only, no external stores,
and Veteran skill. MiG-29S starts with 1,750 kg fuel; MiG-21bis with 1,400 kg.
The opponent starts at your altitude and matches your current velocity magnitude,
clamped to 150–350 m/s. Position uses the horizontal projection of your nose heading.
Set up in approximately level flight. A spawn is refused if its location has less
than 1,000 feet of terrain clearance; the existing fight is kept.

The opponent receives an attack task against your group after a one-second controller
initialization delay. There is no ready call or merge gate: the AI can maneuver and
fire as soon as it engages. These are initial geometries, not scripted maneuvers.
Terrain clearance checks cover the spawn point, not the entire subsequent fight.

**Reset last opponent** replaces it using your current position and the last successful
aircraft/setup selection. **Remove opponent** removes only your group's BFM opponent
and retains the selection for reset. Selecting another setup also replaces the old
opponent, after the new spawn succeeds.

Multiplayer menus and fights are shared by a flight group. The first living airborne
player in group unit order supplies the position, even if a wingman chooses the menu.
Use separate mission groups for independent fights. Opponents are tasked against
their owning player group, but the simulator does not isolate fights from other
aircraft or defensive reactions. When the group has no airborne players left, its
opponent is removed on the next five-second check. When no players remain in the
group, its menu and saved selection are removed too.

## Optional settings

Replace `BFM.init()` with, for example:

```lua
BFM.init({
    opponentCountry = country.id.CJTF_RED, -- must be assigned to RED
    neutralDistanceNm = 2,
    tailDistanceNm = 0.7,
    minimumClearanceFeet = 1000,
    skill = BFM.Skill.VETERAN,
})
```

Skill names match the aircraft Mission Editor labels:

| Configuration | DCS internal value |
| --- | --- |
| `BFM.Skill.CADET` | `Cadet` |
| `BFM.Skill.ROOKIE` | `Average` |
| `BFM.Skill.TRAINED` | `Good` |
| `BFM.Skill.VETERAN` (default) | `High` |
| `BFM.Skill.ACE` | `Excellent` |
| `BFM.Skill.RANDOM` | `Random` |

The original `AVERAGE`, `GOOD`, `HIGH`, and `EXCELLENT` constants remain aliases
so existing mission configuration continues to work. Cadet requires a DCS version
that supports that aircraft skill level.

Change configuration before initialization, then restart the mission to apply changes.
Your own loadout is controlled by the Mission Editor; the script does not disarm players.

## Verification

Local mocked-DCS tests: run `lua tests/BFM_test.lua` from this directory with Lua 5.1.
These check menu lifecycle, spawn geometry, task targeting, reset/removal isolation,
terrain rejection, and delayed-controller behavior. They do not simulate DCS AI or
validate aircraft payload acceptance in the running simulator.

In DCS, try both aircraft and all three setups over flat terrain. Confirm heading,
altitude, guns-only loadout, and engagement. Then check reset/removal, a late join,
death/respawn, and two independent player groups. Check `Saved Games/DCS.../Logs/dcs.log`
for script errors. These in-mission checks are still required.

References used: [Hoggit scripting reference](https://wiki.hoggitworld.com/view/Simulator_Scripting_Engine_Documentation),
[dynamic groups and controller delay](https://wiki.hoggitworld.com/view/DCS_func_addGroup),
[AttackGroup](https://wiki.hoggitworld.com/view/DCS_task_attackGroup), and
[group radio commands](https://wiki.hoggitworld.com/view/DCS_func_addCommandForGroup).
