//=============================================================================
// InfectionPupae
// Player-controlled SkaarjPupae: the fire button triggers the stock melee
// attack instead of an AI chase. Tier 0 of the infection evolution.
//=============================================================================
class InfectionPupae extends SkaarjPupae;

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

// A player-possessed monster must NEVER get the player's human character
// mesh applied - xPawn.PostNetReceive() would otherwise swap this Pupae's
// mesh for the player's ("BotD" etc), breaking every monster animation.
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
