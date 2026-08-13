//=============================================================================
// InfectionSkaarj
// Player-controlled Skaarj: fire button triggers the stock attack
// (melee + projectiles). Tier 2 of the infection evolution.
//=============================================================================
class InfectionSkaarj extends Skaarj;

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

// Never let xBot.Possess()/xPawn.Setup() swap this monster's mesh for a
// human character - the horde must keep its monster look (and animations).
simulated function Setup(xUtil.PlayerRecord rec, optional bool bLoadNow)
{
}

defaultproperties
{
     AttackCooldown=1.000000
}
