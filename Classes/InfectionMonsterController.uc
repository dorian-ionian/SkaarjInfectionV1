//=============================================================================
// InfectionMonsterController
// Grudge AI for the AI horde monsters: never forgets the nearest human,
// always charges, never camps, and self-recovers from stuck terrain by
// teleporting next to its target. Built on the proven MonsterArmyV1
// controller pattern (minus the multi-pack damage fallback - the stock
// SkaarjPack attacks work fine here).
//=============================================================================
class InfectionMonsterController extends MonsterController;

var Pawn GrudgeEnemy;
var bool bPosTracked;
var vector TrackPos;
var int StuckEntries;
var int AnimWaitTicks;

function SetGrudge(Pawn Other)
{
    GrudgeEnemy = Other;
    if (GrudgeEnemy != None)
    {
        Enemy = GrudgeEnemy;
        Target = GrudgeEnemy;
    }
}

// Drop the grudge entirely - the monster returns to stock roaming/AI.
function ClearGrudge()
{
    GrudgeEnemy = None;
    Enemy = None;
    Target = None;
}

// Only acquire a grudge when a human is within the configured hunt range -
// otherwise the horde would be omniscient and swarm from across the map.
function Pawn FindNearestHuman()
{
    local SkaarjInfectionGame G;
    local Monster M;
    local float Range;

    if (Pawn == None || Level.Game == None)
        return None;
    G = SkaarjInfectionGame(Level.Game);
    if (G == None)
        return None;
    M = Monster(Pawn);
    if (M == None)
        return None;
    Range = G.HordeHuntRange;
    return G.FindNearestHuman(M, Range);
}

function bool GrudgeAlive()
{
    if (GrudgeEnemy == None || GrudgeEnemy.Health <= 0 || GrudgeEnemy.bDeleteMe)
    {
        SetGrudge(FindNearestHuman());
        return (GrudgeEnemy != None && GrudgeEnemy.Health > 0 && GrudgeEnemy.Controller != None);
    }
    return true;
}

function bool FindNewEnemy()
{
    if (GrudgeAlive())
    {
        if (Enemy != GrudgeEnemy)
            ChangeEnemy(GrudgeEnemy, CanSee(GrudgeEnemy));
        return true;
    }
    return Super.FindNewEnemy();
}

function ExecuteWhatToDoNext()
{
    if (GrudgeAlive() && Enemy != GrudgeEnemy)
        Enemy = GrudgeEnemy;
    Super.ExecuteWhatToDoNext();
}

function WanderOrCamp(bool bMayCrouch)
{
    if (GrudgeAlive())
    {
        Enemy = GrudgeEnemy;
        GotoState('Charging');
        return;
    }
    Super.WanderOrCamp(bMayCrouch);
}

function ChooseAttackMode()
{
    if (GrudgeAlive() && Enemy != GrudgeEnemy)
        Enemy = GrudgeEnemy;
    if (Enemy == None || Pawn == None)
        return;
    // Range-only check: CanAttack() is a bodyless declaration in
    // Monster.uc that returns false for monsters that don't override it.
    if (VSize(Enemy.Location - Pawn.Location)
        < Pawn.MeleeRange + Pawn.CollisionRadius + Enemy.CollisionRadius + 100)
        DoRangedAttackOn(Enemy);
    else
        DoCharge();
}

function DoTacticalMove()
{
    GotoState('Charging');
}

state RestFormation
{
Begin:
    if (GrudgeAlive())
    {
        Enemy = GrudgeEnemy;
        GotoState('Charging');
    }
    else
    {
        WaitForLanding();
        Pawn.Acceleration = vect(0,0,0);
        Sleep(1.0);
        Goto('Begin');
    }
}

state Charging
{
ignores SeePlayer, HearNoise;

    function MayFall()
    {
        if (MoveTarget != Enemy)
            return;
        Pawn.bCanJump = ActorReachable(Enemy);
        if (!Pawn.bCanJump)
            MoveTimer = -1.0;
    }

    event bool NotifyBump(actor Other)
    {
        if (Other == Enemy || Other == GrudgeEnemy)
        {
            if (Enemy == None)
                Enemy = GrudgeEnemy;
            if (Enemy != None)
                DoRangedAttackOn(Enemy);
            return false;
        }
        return Global.NotifyBump(Other);
    }

    function Timer()
    {
        enable('NotifyBump');
        Target = Enemy;
        TimedFireWeaponAtEnemy();
    }

    function EnemyNotVisible()
    {
        if (GrudgeAlive())
        {
            Enemy = GrudgeEnemy;
            GotoState('Charging');
        }
        else
            WhatToDoNext(15);
    }

    function EndState()
    {
        if ((Pawn != None) && Pawn.JumpZ > 0)
            Pawn.bCanJump = true;
    }

    function bool StrafeFromDamage(float Damage, class<DamageType> DamageType, bool bFindDest)
    {
        if (Enemy == None || Pawn == None)
            return false;
        return Super.StrafeFromDamage(Damage, DamageType, bFindDest);
    }

    function bool TryStrafe(vector sideDir)
    {
        return true;
    }

Begin:
    if (Pawn.Physics == PHYS_Falling && Enemy != None)
    {
        Focus = Enemy;
        Destination = Enemy.Location;
        WaitForLanding();
    }
    if (GrudgeAlive() && Enemy != GrudgeEnemy)
        Enemy = GrudgeEnemy;
    if (Enemy == None)
    {
        WaitForLanding();
        Pawn.Acceleration = vect(0,0,0);
        Sleep(0.5);
        Goto('Begin');
    }
WaitForAnim:
    if (Monster(Pawn).bShotAnim)
    {
        Sleep(0.35);
        AnimWaitTicks++;
        if (AnimWaitTicks < 6)
            Goto('WaitForAnim');
        AnimWaitTicks = 0;
        Monster(Pawn).bShotAnim = false;
    }

    if (bPosTracked && VSize(Pawn.Location - TrackPos) < 120)
    {
        StuckEntries++;
        if (StuckEntries >= 3)
        {
            StuckEntries = 0;
            TeleportNextToEnemy();
        }
    }
    else
    {
        StuckEntries = 0;
        bPosTracked = true;
        TrackPos = Pawn.Location;
    }

    if (!FindBestPathToward(Enemy, false, true))
        MoveTarget = Enemy;

Moving:
    MoveToward(MoveTarget, FaceActor(1), 1.0);

    if (Enemy != None && VSize(Enemy.Location - Pawn.Location)
        < Pawn.MeleeRange + Pawn.CollisionRadius + Enemy.CollisionRadius + 100)
        DoRangedAttackOn(Enemy);

    WhatToDoNext(17);
    Goto('Begin');
}

function TeleportNextToEnemy()
{
    local vector Spot, HitLoc, HitNorm;
    local Actor Hit;
    local int i;
    local float A;

    if (Enemy == None || Pawn == None)
        return;

    for (i = 0; i < 16; i++)
    {
        A = i * 0.392699;
        Spot = Enemy.Location;
        Spot.X += Cos(A) * (100 + FRand() * 200);
        Spot.Y += Sin(A) * (100 + FRand() * 200);
        Spot.Z += 40;
        Hit = Trace(HitLoc, HitNorm, Spot, Enemy.Location, false, Pawn.GetCollisionExtent());
        if (Hit == None)
        {
            Pawn.SetLocation(Spot);
            Pawn.SetPhysics(PHYS_Falling);
            Pawn.Velocity = vect(0,0,0);
            Pawn.SetRotation(rotator(Enemy.Location - Spot));
            SetRotation(rotator(Enemy.Location - Spot));
            return;
        }
    }

    Spot = Enemy.Location + vect(0, 1, 0) * (Pawn.CollisionRadius + Enemy.CollisionRadius + 40);
    Pawn.SetLocation(Spot);
    Pawn.SetPhysics(PHYS_Falling);
    Pawn.Velocity = vect(0,0,0);
}

defaultproperties
{
}
