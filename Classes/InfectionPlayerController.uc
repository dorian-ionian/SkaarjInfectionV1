//=============================================================================
// InfectionPlayerController
// Custom player controller for the infection gametype.
//
// WHY THE RPC: the Fire key is bound to the "Fire" exec, which runs on the
// CLIENT - and clients have no Level.Game, so the monster pawn's Fire()
// can't resolve targets or deal damage there. The exec therefore forwards
// to a reliable server RPC that performs the actual attack (find nearest
// human, aim, RangedAttack) so damage is applied authoritatively.
//=============================================================================
class InfectionPlayerController extends xPlayer;

replication
{
    reliable if (Role < ROLE_Authority)
        ServerMonsterAttack;
}

simulated function PostBeginPlay()
{
    Super.PostBeginPlay();
    if (Role == ROLE_Authority)
        log("InfectionPlayerController: active for player", 'SkaarjInfectionV1');
}

// Fire button: player-controlled monsters attack server-side. Humans keep
// the stock weapon path.
exec function Fire(optional float F)
{
    if (Monster(Pawn) != None)
        ServerMonsterAttack();
    else
        Super.Fire(F);
}

exec function AltFire(optional float F)
{
    if (Monster(Pawn) != None)
        ServerMonsterAttack();
    else
        Super.AltFire(F);
}

// Server-side monster attack: find the nearest living human, face them and
// trigger the monster's own RangedAttack (anims, melee, projectiles).
function ServerMonsterAttack()
{
    local Monster M;
    local SkaarjInfectionGame G;
    local Pawn T;

    if (Role < ROLE_Authority)
        return;
    M = Monster(Pawn);
    if (M == None || M.Health <= 0 || M.bDeleteMe)
        return;
    G = SkaarjInfectionGame(Level.Game);
    if (G == None)
        return;
    T = G.FindNearestHuman(M, G.AttackRange);
    if (T == None)
        return;
    // aim the monster at the victim (melee checks trace forward)
    M.SetRotation(rotator(T.Location - M.Location));
    SetRotation(rotator(T.Location - M.Location));
    Target = T;               // the monster's MeleeDamageTarget reads this
    M.RangedAttack(T);
    log("INF-ATK: " $ M.Class $ " -> " $ T.Class, 'SkaarjInfectionV1');
}

defaultproperties
{
     PlayerReplicationInfoClass=Class'XGame.xPlayerReplicationInfo'
}
