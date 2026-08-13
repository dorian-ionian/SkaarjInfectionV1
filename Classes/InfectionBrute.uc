//=============================================================================
// InfectionBrute
// Player-controlled Brute: fire button triggers the stock attack (rocket
// launcher + melee). Tier 3 of the infection evolution.
//=============================================================================
class InfectionBrute extends Brute;

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

defaultproperties
{
     AttackCooldown=1.200000
}
