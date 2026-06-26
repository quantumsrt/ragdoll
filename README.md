# Roblox Sphere Ragdoll System (R6)

A ragdoll system for **R6** characters that **collides with invisible spheres
instead of the limb blocks**.

## Why spheres?

R6 limbs are blocks. When a ragdoll's block limbs collide with the world they
snag on edges, jitter against seams, and clip through corners — the classic
"ragdoll caught on a doorframe and vibrating" look.

This system disables collision on each of the six limbs and welds a transparent,
collidable **sphere** inside each one. Spheres can't catch on a corner, so the
body tumbles and settles smoothly and naturally. The visible limbs ride along
via the original joints (swapped from rigid `Motor6D`s to floppy
`BallSocketConstraint`s), so the character still looks right while the hidden
spheres do all the colliding.

```
 visible limb (CanCollide = false)        invisible sphere (CanCollide = true)
        ┌──────────┐                                  ╭───╮
        │  arm     │   ◀── welded together ──▶       (     )
        └──────────┘                                  ╰───╯
   looks correct, never collides            rolls over geometry, never snags
```

## Layout

| Path | What it is |
| --- | --- |
| `src/ReplicatedStorage/Ragdoll/init.luau` | The reusable `Ragdoll` module. |
| `src/ServerScriptService/RagdollService.server.luau` | Auto-ragdolls on death + a `ToggleRagdoll` remote. |
| `src/StarterPlayer/StarterPlayerScripts/RagdollToggle.client.luau` | Press **R** to toggle your ragdoll. |
| `default.project.json` | [Rojo](https://rojo.space) project mapping. |

## Quick start

With [Rojo](https://rojo.space):

```sh
rojo serve
```

then connect from Roblox Studio. In play mode, press **R** to flop over and
again to stand up; characters also ragdoll automatically when they die.

## Using the module directly

```lua
local Ragdoll = require(game.ReplicatedStorage.Ragdoll)

local ragdoll = Ragdoll.new(character, {
    SphereScale = 1,        -- sphere diameter = min(limb size) * scale
    ShowSpheres = false,    -- set true to see the collision spheres
    CollisionGroup = "",    -- spheres ignore each other when set
})

ragdoll:Activate()    -- go limp
ragdoll:Deactivate()  -- stand back up (fully reversible)
ragdoll:Destroy()     -- clean up
```

## Configuration

| Option | Default | Description |
| --- | --- | --- |
| `SphereScale` | `1` | Sphere diameter as a multiple of the limb's smallest dimension (keeps the sphere snug inside the limb). |
| `ShowSpheres` | `false` | Render the spheres semi-transparent for debugging. |
| `BallSocketUpperAngle` | `45` | Swing limit on each joint, in degrees. |
| `BallSocketTwistLower` / `BallSocketTwistUpper` | `-45` / `45` | Twist limits, in degrees. |
| `CollisionGroup` | `""` | Collision group for the spheres. `RagdollService` sets one up so players don't shove each other. |

## How it works

`:Activate()`:

1. Disables the engine's own `Ragdoll`, `FallingDown` and `GettingUp` states,
   puts the `Humanoid` into the `Physics` state, and sets `PlatformStand` so
   vanilla balance can't tip the character over or fight the custom ragdoll.
2. Replaces the five torso joints (`Neck`, `Left/Right Shoulder`,
   `Left/Right Hip`) with `BallSocketConstraint`s built from attachments at each
   joint's `C0` / `C1`. The `RootJoint` is left intact so the rig stays in one
   piece. Each `Motor6D` is only *disabled*, never destroyed, so the rig
   restores exactly.
3. Sets `CanCollide = false` on each of the six limbs and welds a transparent
   collision sphere inside it.

`:Deactivate()` reverses all of it: destroys the sockets, attachments, welds and
spheres, re-enables the motors, and re-collides the limbs. Before handing control
back it snaps the `HumanoidRootPart` upright (keeping only its yaw) and zeroes
every part's velocity, so the character stands up cleanly instead of toppling
from leftover ragdoll angle or momentum. Then it returns the Humanoid to the
`GettingUp` state. Activation is fully reversible.
