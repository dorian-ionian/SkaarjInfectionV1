//=============================================================================
// InfectionKrall
// Player-controlled Krall: fire button triggers the stock attack
// (melee + bolt). Tier 1 of the infection evolution.
//=============================================================================
class InfectionKrall extends Krall;

var float NextAttackTime;
var() float AttackCooldown;

function Fire(optional float F)
{
    local SkaarjInfectionGame G;
    local Pawn T;

    if (Controller == None || !Controller.bIsPlayer)
    {
        Super.Fire(F);
        return;
    }
    G = SkaarjInfectionGame(Level.Game);
    if (G == None)
    {
        Super.Fire(F);
        return;
    }
    if (Level.TimeSeconds < NextAttackTime)
        return;
    T = G.FindNearestHuman(self, 950);
    if (T == None)
        return;
    Controller.Target = T;
    RangedAttack(T);
    NextAttackTime = Level.TimeSeconds + AttackCooldown;
}

// Never let xPawn.PostNetReceive() swap this monster's mesh for the
// player's human character mesh.
simulated event PostNetReceive()
{
    bNetNotify = false;
}

defaultproperties
{
     AttackCooldown=1.200000
}
