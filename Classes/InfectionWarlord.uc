//=============================================================================
// InfectionWarlord
// Player-controlled WarLord: fire button triggers the stock attack
// (rocket volleys + melee). Tier 4 (apex) of the infection evolution.
//=============================================================================
class InfectionWarlord extends WarLord;

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
    T = G.FindNearestHuman(self, 1200);
    if (T == None)
        return;
    Controller.Target = T;
    RangedAttack(T);
    NextAttackTime = Level.TimeSeconds + AttackCooldown;
}

defaultproperties
{
     AttackCooldown=1.500000
}
