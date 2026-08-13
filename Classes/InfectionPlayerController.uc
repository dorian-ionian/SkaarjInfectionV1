//=============================================================================
// InfectionPlayerController
// Custom player controller for the infection gametype. The stock xPlayer
// routes the fire button through the pawn's Weapon/Inventory chain, which
// does nothing for a monster pawn - so infected players get their attack
// wired to the monster's own Fire() instead, and the AI attack cooldown is
// disabled while a human is at the wheel.
//=============================================================================
class InfectionPlayerController extends xPlayer;

// Forward the fire button to the monster pawn's own attack. The stock
// PlayerController already calls Pawn.Fire() - but the Pawn class passes
// it to the inventory chain; monsters need their own Fire() to run, and
// they need the AI attack cooldown disabled while human-controlled.
function Fire(float F)
{
    local Monster M;

    M = Monster(Pawn);
    if (M != None)
    {
        // the monster pawn's own Fire() runs the stock attack (RangedAttack
        // chain) - bypass the weapon/inventory requirement entirely
        M.Fire(F);
        return;
    }
    Super.Fire(F);
}

defaultproperties
{
     PlayerReplicationInfoClass=Class'XGame.xPlayerReplicationInfo'
}
