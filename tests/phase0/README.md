# Phase 0 characterization

This directory records the behavior that the MVC migration must preserve. The
test scene instantiates the real `chess_game.tscn`, including its current Model,
Controller, View, animations, effects, and UI wiring. It intentionally does not
provide a headless substitute for any of those dependencies.

Run the automated characterization scene with Godot 4.4 or newer:

```sh
godot --headless --path . tests/phase0/phase0_characterization.tscn
```

The process exits with status 0 after printing `PHASE 0 CHARACTERIZATION: PASS`,
or status 1 after listing failures.

Known baseline diagnostic: explosion instances currently call `play("explode")`,
while `effects/explosion.tscn` contains an animation named `default`. Rage and
destruction scenarios therefore log Godot animation errors even when all rule
assertions pass. Phase 0 records this existing behavior and does not repair it.

The automated checks preserve these current contracts:

- battle control supports player-vs-player, player-vs-CPU, and CPU-vs-CPU;
- the default board initializes with 32 pieces and White to move;
- pawn two-step movement, action locking, last-move state, movement animation,
  and turn completion occur as one resolved action;
- attacks against surviving multi-HP defenders lunge to the target and return
  before the action completes, without changing the attacker's board square;
- Arakne Spike Burst damages its target, consumes the action, and starts its
  cooldown;
- Charge stops adjacent to a surviving king and finishes its movement animation
  before the turn changes;
- Minotaur Rage is queued after surviving damage, waits for its current intro
  animation, damages adjacent pieces, and then completes the action;
- Rage reactions remain ahead of already-queued Raise Dead choices;
- Raise Dead can target the defeated piece's square after Rage leaves it empty;
- Bone Pawns summoned on their opposite back rank are immediately destroyed;
- Raise Dead pauses the action in the Controller's current non-move selection
  mode, then resumes the queue after a valid choice;
- defeating a king completes the battle, reports the winner, and leaves input
  locked.

Manual checks remain necessary for presentation details that should not be made
fragile pixel assertions during this migration:

1. Board, pieces, HP bars, highlights, cooldown buttons, and result overlay look
   unchanged.
2. Castling animates the rook before the king.
3. En passant removes the adjacent pawn and then moves the attacker.
4. Promotion replaces the pawn representation with a Queen.
5. Charge aura/audio start on targeting and stop on selection/cancellation.
6. Charge into a wall moves the Minotaur and applies stun stars.
7. Rage grows and restores the Minotaur before adjacent explosions/damage.
8. Raise Dead shows the Necromancer aura only while its selection is active.
