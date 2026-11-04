# Baseball bat and destruction animation plan

## Playable now

Pick up the wooden baseball bat beside the east staff-security entrance with **T** or by clicking it. **J** alternates forehand and backhand swings; **K** performs an overhead smash. Hold right mouse to face a target. **G** places it gently; **T** still throws it. Controls respect remapped keys and appear in the nearby action circles.

| Animation | Timing | Motion and feedback |
| --- | --- | --- |
| Pickup | 0.32 s | Existing reach/lift transitions into a two-handed bat grip. |
| Armed idle/walk | While equipped | Bat rests diagonally beside the shoulder; hands track handle positions. Walking keeps the existing foot cycle. |
| Forehand | Contact 0.28 s; finish 0.72 s | Shoulder windup, horizontal barrel sweep, hip turn, follow-through, return to guard. |
| Backhand | Contact 0.30 s; finish 0.76 s | Reversed sweep and hip turn, selected by consecutive light strikes. |
| Overhead smash | Contact 0.48 s; finish 1.10 s | Raise above head, downward arc, low follow-through, slower recovery. |
| Blocked swing | At wall contact | Stop collision sampling at the obstruction; recoil and return to guard. |
| NPC impact | On accepted contact | Relative bat speed sets damage and momentum. Jolt drives translation, yaw, gravity and obstacle collisions. Existing skeleton poses supply high/body recoil, fall and recovery. |
| Break burst | First 0.32 s | Material chips, a widening floor pulse, and physical family parts. |
| Debris flow | Starts after 0.055 s | Narrow directional dust plume grows and fades; light fragments tumble more quickly. |
| Debris settling | 3.5–6 s | Material-specific friction, bounce and drag, followed by a short shrink/fade and cleanup. |

`BaseballBat.local_pose()` is the shared motion source for the visible bat, hand grips, barrel trail and collision samples. `BatStrike` samples a capsule through the active swing at 180 Hz, including skipped frames, deduplicates contacts, checks walls and supports seated NPCs. A swing can contact multiple people or objects along its path. Downed, protected and departing NPCs keep their existing combat protections.

`HitMotion` is a temporary 72 kg rigid-body motor. It receives a contact impulse using reduced mass and relative swing speed, then lets Jolt calculate movement and collision response. It restores ordinary character movement on recovery or reset. This is a physics-driven body reaction with animated limbs; it is not a full jointed ragdoll. The standing capsule remains the collision proxy during the fall.

Effects retain the existing caps of 80 physical fragments and 24 material effects. Pausing freezes both effects and physics. Bat rotation, damage and thrown state use the existing prop save/load format; an equipped bat restores released, as other props do.

## Next animation passes

1. **Grip polish:** curl fingers around the handle, align palms to bat roll, and add a softer shoulder carry loop. Pickup already blends from the object's actual resting orientation.
2. **More strikes:** add a low sweep for small objects, a running swing, and an optional charge-and-release smash. Give each its own active window and keep collision samples derived from the visible motion.
3. **Directional reactions:** add left/right stumble clips and dedicated back/side landings, selected from contact direction and impulse strength. Blend to planted recovery only after the physics body settles.
4. **Jointed ragdolls:** add torso, pelvis and limb bodies with joint limits; transfer contact impulse to the struck body, then recover from a safe floor pose. Verify against desks, seated starts and narrow doorways before replacing the current motor.
5. **Richer debris flow:** author paper flutter, wood splinters, glass glints and settling dust per family. Pool emitters only if profiling shows allocation spikes; retain the global budgets.

For every pass, verify contacts against the visible barrel, low-frame-rate sweeps, intervening walls, moving/seated NPCs, one hit per body per swing, interrupted pickup, safe dropping, save/load, pause/resume, and complete cleanup. The current implementation is covered by `tests/baseball_bat_regression.gd` and the existing combat, props, material-destruction and save suites.
