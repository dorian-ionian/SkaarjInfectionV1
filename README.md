# SkaarjInfectionV1 — asymmetric infection for UT2004

Everyone starts human. Die as a human and you come back as a monster on
the infected team. Kill humans to evolve. Last humans standing when the
round clock expires win.

## The evolution chain

| Tier | Points | Monster     |
|------|--------|-------------|
| 0    | 0      | Pupae       |
| 1    | 2      | Krall       |
| 2    | 5      | Skaarj      |
| 3    | 9      | Brute       |
| 4    | 14     | WarLord     |

Each human kill pays `PointsForKill` evolution points. Evolution applies
on your next respawn, and every stage also gets +40 max HP and +30 ground
speed per tier.

## How it plays

- **Humans (team 0)** have full weapon loadouts. Win a round by keeping
  at least one human alive until the round clock expires.
- **Infected (team 1)** are player-controlled stock Skaarj monsters:
  press fire to attack (melee for Pupae, melee+projectiles up the chain).
  Win by consuming every human.
- **No voluntary team switching** — infection is the only way to change
  sides. Bots always play as humans.
- Rounds are best-of-N; between rounds the infection recedes and everyone
  respawns human.

## Running

```
ucc server DM-Rankin?game=SkaarjInfectionV1.SkaarjInfectionGame -ini=UT2004SkaarjInfection.ini
```

or `RunServerSkaarjInfection.bat` (auto-restarts on crash).

## Configuration (System\SkaarjInfectionV1.ini)

`[SkaarjInfectionV1.SkaarjInfectionGame]` — round length, best-of-N,
points per kill, evolution thresholds.

URL options: `?RoundTimeLimit=`, `?RoundsPerMatch=`, `?PointsForKill=`,
`?TimeLimit=`.

## Notes & v1 limitations

- Infected players attack with the fire button (stock monster attacks).
  Alt-fire is unused; there is no HUD for evolution points yet (they're
  announced).
- The WarLord stage flies (stock WarLord physics).
- Bots are humans only; they never get infected.
