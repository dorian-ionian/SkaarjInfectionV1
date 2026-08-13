//=============================================================================
// SkaarjInfectionGame
//
// Asymmetric infection for UT2004. Everyone starts as a human (team 0).
// When a human dies they are INFECTED: they switch to team 1 and respawn
// as a player-controlled monster. Infected earn evolution points for
// killing humans and evolve down the Skaarj chain on respawn:
//
//   Pupae -> Krall -> Skaarj -> Brute -> WarLord
//
// Humans win a round if anyone survives the round clock; the infected
// win when no humans are left. Best-of-N rounds, endless matchups.
//=============================================================================
class SkaarjInfectionGame extends xTeamGame
    config(SkaarjInfectionV1);

//------------------------------------------------------------------------------
// Configurable settings (System\SkaarjInfectionV1.ini)
//------------------------------------------------------------------------------
var() config int    RoundTimeLimit;     // seconds per round (default 240)
var() config int    RoundsPerMatch;     // best-of-N rounds (default 3)
var() config int    PointsForKill;      // evolution points per human kill (default 2)
var() config int    EvolveAt[5];        // points needed for each tier
var() config float  ResultTime;         // seconds to linger on a result (default 5)
var() config float  IntermissionTime;   // seconds between matchups (default 8)

const PHASE_IDLE         = 0;
const PHASE_FIGHT        = 1;
const PHASE_RESULT       = 2;
const PHASE_INTERMISSION = 3;

var int  Phase;
var int  RoundNumber;
var int  MatchupNumber;
var int  RoundWins[2];          // [0] = humans, [1] = infected
var int  TotalWins[2];
var float PhaseClock;
var bool bShowStarted;
var bool bMatchupOver;
var bool bDriverActive;
var bool bLastHumanWarned;

var array<Controller> InfectedList;
var array<int> InfectedPoints;
var array<int> InfectedTier;

//==============================================================================
// Initialization
//==============================================================================

event InitGame(string Options, out string Error)
{
    Super.InitGame(Options, Error);

    RoundTimeLimit = Max(30, GetIntOption(Options, "RoundTimeLimit", default.RoundTimeLimit));
    RoundsPerMatch = Clamp(GetIntOption(Options, "RoundsPerMatch", default.RoundsPerMatch), 1, 9);
    PointsForKill  = Max(1, GetIntOption(Options, "PointsForKill", default.PointsForKill));

    TimeLimit = Clamp(GetIntOption(Options, "TimeLimit", TimeLimit), 0, 480);
    RemainingTime = 60 * TimeLimit;
    if (GameReplicationInfo != None)
        GameReplicationInfo.TimeLimit = TimeLimit;

    MaxLives = 0;          // nobody ever runs out - they just change sides
    bForceRespawn = true;
    bWaitForNetPlayers = false;
    MinNetPlayers = 0;

    // No stock DM bots - the horde is the "bot team". bAutoNumBots/NeedPlayers
    // would otherwise keep adding/removing stock bots as players join/leave.
    MinPlayers = 0;
    InitialBots = 0;
    bAutoNumBots = false;
    bBalanceTeams = false;
    bPlayersBalanceTeams = false;

    HordeMax        = Max(0, GetIntOption(Options, "HordeMax", default.HordeMax));
    HordeInterval   = Max(2, float(GetIntOption(Options, "HordeInterval", int(default.HordeInterval))));
    HordeHealthBonus = Max(0, GetIntOption(Options, "HordeHealthBonus", default.HordeHealthBonus));
    HordeDamageBonus = Max(0, GetIntOption(Options, "HordeDamageBonus", default.HordeDamageBonus));

    log("SkaarjInfection: init - round " $ RoundTimeLimit $ "s best of " $ RoundsPerMatch
        $ " horde " $ HordeMax $ " every " $ int(HordeInterval) $ "s", 'SkaarjInfectionV1');
}

function PostBeginPlay()
{
    Super.PostBeginPlay();
    if (Role == ROLE_Authority)
    {
        bDriverActive = (Spawn(class'SkaarjInfectionDriver') != None);
        if (!bDriverActive)
            log("SkaarjInfection: could not spawn driver", 'SkaarjInfectionV1');
    }
}

// Everyone joins as a human. Team 1 exists only for the infected.
function byte PickTeam(byte num, Controller C)
{
    return 0;
}

function UnrealTeamInfo GetBotTeam(optional int TeamBots)
{
    return Teams[0];
}

// No voluntary team switching - infection is the only way to change sides.
function bool ChangeTeam(Controller Other, int num, bool bNewTeam)
{
    if (bNewTeam)
        return false;
    return Super.ChangeTeam(Other, num, bNewTeam);
}

// The horde is the only "bot" force - the stock bot management must never
// add/remove DM bots to fill the server.
function bool NeedPlayers()
{
    return false;
}

function bool TooManyBots(Controller botToRemove)
{
    return true;
}

//==============================================================================
// Horde (AI infected monsters)
//==============================================================================

function int CountHorde()
{
    local int i, n;
    for (i = 0; i < HordeMonsters.Length; i++)
        if (HordeMonsters[i] != None && HordeMonsters[i].Health > 0 && !HordeMonsters[i].bDeleteMe)
            n++;
    return n;
}

function class<Monster> GetHordeClass()
{
    local int r;
    r = Rand(5);
    if (r == 0)
        return class'SkaarjPack.Skaarj';
    if (r == 1)
        return class'SkaarjPack.Krall';
    if (r == 2)
        return class'SkaarjPack.EliteKrall';
    if (r == 3)
        return class'SkaarjPack.FireSkaarj';
    return class'SkaarjPack.Brute';
}

function Monster SpawnHordeMonster()
{
    local class<Monster> MC;
    local NavigationPoint S;
    local Monster M;
    local InfectionMonsterController C;
    local Pawn T;

    MC = GetHordeClass();
    S = FindPlayerStart(None, 1);
    if (S == None)
        return None;
    M = Spawn(MC,,, S.Location + vect(0, 0, 30), S.Rotation);
    if (M == None)
        return None;
    M.DeactivateSpawnProtection();
    M.HealthMax = M.Health + HordeHealthBonus;
    M.Health = M.HealthMax;
    if (M.Controller != None)
        M.Controller.Destroy();
    C = Spawn(class'InfectionMonsterController');
    if (C != None)
    {
        C.Possess(M);
        C.InitializeSkill(7.0);
        T = FindNearestHuman(M, 99999);
        if (T != None)
            C.SetGrudge(T);
    }
    HordeMonsters[HordeMonsters.Length] = M;
    return M;
}

function CleanupHorde()
{
    local int i;
    local InfectionMonsterController C;
    local array<InfectionMonsterController> Ghosts;

    for (i = HordeMonsters.Length - 1; i >= 0; i--)
    {
        if (HordeMonsters[i] == None || HordeMonsters[i].Health <= 0 || HordeMonsters[i].bDeleteMe)
            HordeMonsters.Remove(i, 1);
    }
    foreach DynamicActors(class'InfectionMonsterController', C)
        if (C.Pawn == None)
            Ghosts[Ghosts.Length] = C;
    for (i = 0; i < Ghosts.Length; i++)
        if (Ghosts[i] != None)
            Ghosts[i].Destroy();
}

function SpawnHordeWave()
{
    local int i, n;
    n = HordeMax - CountHorde();
    if (n <= 0)
        return;
    if (n > 3)
        n = 3;
    for (i = 0; i < n; i++)
        SpawnHordeMonster();
}

//==============================================================================
// Show flow
//==============================================================================

function StartMatch()
{
    Super.StartMatch();
    StartShow();
}

function StartShow()
{
    if (bShowStarted)
        return;
    bShowStarted = true;
    Phase = PHASE_IDLE;
    RemainingTime = 60 * TimeLimit;
    if (GameReplicationInfo != None)
        GameReplicationInfo.RemainingTime = RemainingTime;
    StartNewMatchup();
}

function StartNewMatchup()
{
    MatchupNumber++;
    RoundNumber = 1;
    RoundWins[0] = 0;
    RoundWins[1] = 0;
    bMatchupOver = false;
    Broadcast(Self, "MATCHUP " $ MatchupNumber $ ": HUMANITY VS THE SKAARJ INFECTION!", 'CriticalEvent');
    StartRound();
}

function StartRound()
{
    Phase = PHASE_FIGHT;
    PhaseClock = 0;
    bLastHumanWarned = false;
    HordeClock = 0;
    bHordePaused = false;
    CureEveryone();   // no-one carries infection into the next round
    CleanupHorde();
    Broadcast(Self, "ROUND " $ RoundNumber $ " OF " $ RoundsPerMatch $ ": SURVIVE - OR JOIN THE HORDE!", 'CriticalEvent');
}

//==============================================================================
// Infection bookkeeping
//==============================================================================

function int FindInfectedIndex(Controller C)
{
    local int i;
    for (i = 0; i < InfectedList.Length; i++)
        if (InfectedList[i] == C)
            return i;
    return -1;
}

function int AddInfected(Controller C)
{
    local int i;
    i = FindInfectedIndex(C);
    if (i >= 0)
        return i;
    InfectedList[InfectedList.Length] = C;
    InfectedPoints[InfectedPoints.Length] = 0;
    InfectedTier[InfectedTier.Length] = 0;
    return InfectedList.Length - 1;
}

function bool IsInfected(Controller C)
{
    return (FindInfectedIndex(C) >= 0);
}

// A human died - they join the horde.
function ConvertToInfected(Controller C)
{
    local int i;

    if (C == None || C.PlayerReplicationInfo == None)
        return;
    i = AddInfected(C);
    if (C.PlayerReplicationInfo.bOutOfLives)
        C.PlayerReplicationInfo.bOutOfLives = false;
    ChangeTeam(C, 1, false);
    Broadcast(Self, C.PlayerReplicationInfo.PlayerName $ " HAS BEEN INFECTED!", 'CriticalEvent');
}

// Infected killed a human: evolution points (evolve on next respawn).
function AddInfectionPoints(Controller C, int N)
{
    local int i, NewTier;
    local string ClassName;

    if (C == None || C.PlayerReplicationInfo == None || N <= 0)
        return;
    i = FindInfectedIndex(C);
    if (i < 0)
        i = AddInfected(C);
    InfectedPoints[i] += N;
    NewTier = TierForPoints(InfectedPoints[i]);
    if (NewTier > InfectedTier[i])
    {
        InfectedTier[i] = NewTier;
        ClassName = GetInfectionClassName(NewTier);
        Broadcast(Self, C.PlayerReplicationInfo.PlayerName $ " EVOLVES - NEXT RESPAWN IS A " $ ClassName $ "!", 'CriticalEvent');
    }
}

function int TierForPoints(int Points)
{
    local int i;
    for (i = 4; i > 0; i--)
        if (Points >= EvolveAt[i])
            return i;
    return 0;
}

function string GetInfectionClassName(int Tier)
{
    if (Tier >= 4)
        return "WARLORD";
    if (Tier == 3)
        return "BRUTE";
    if (Tier == 2)
        return "SKAARJ";
    if (Tier == 1)
        return "KRALL";
    return "PUPAE";
}

function class<Monster> GetInfectionClass(int Tier)
{
    if (Tier >= 4)
        return class'InfectionWarlord';
    if (Tier == 3)
        return class'InfectionBrute';
    if (Tier == 2)
        return class'InfectionSkaarj';
    if (Tier == 1)
        return class'InfectionKrall';
    return class'InfectionPupae';
}

//==============================================================================
// Horde damage scaling (horde monsters hit harder than the player horde)
//==============================================================================

function int ReduceDamage(int Damage, pawn injured, pawn instigatedBy, vector HitLocation, out vector Momentum, class<DamageType> DamageType)
{
    local InfectionMonsterController C;

    if (instigatedBy != None)
    {
        C = InfectionMonsterController(instigatedBy.Controller);
        if (C != None)
            Damage += HordeDamageBonus;
    }
    return Super.ReduceDamage(Damage, injured, instigatedBy, HitLocation, Momentum, DamageType);
}

//==============================================================================
// Respawn
//==============================================================================

// Infected players respawn as their evolution stage monster, player-
// controlled. This mirrors GameInfo.RestartPlayer but hands the player a
// monster pawn with no AI controller and no inventory.
function RestartPlayer(Controller aPlayer)
{
    local int idx, Tier, TeamNum;
    local class<Pawn> PC;
    local NavigationPoint StartSpot;
    local Pawn NewPawn;

    if (aPlayer == None || aPlayer.PlayerReplicationInfo == None)
    {
        Super.RestartPlayer(aPlayer);
        return;
    }

    idx = FindInfectedIndex(aPlayer);
    if (idx < 0)
    {
        Super.RestartPlayer(aPlayer);
        return;
    }

    Tier = InfectedTier[idx];
    PC = GetInfectionClass(Tier);
    TeamNum = 1;
    if (aPlayer.PlayerReplicationInfo.Team != None)
        TeamNum = aPlayer.PlayerReplicationInfo.Team.TeamIndex;

    StartSpot = FindPlayerStart(aPlayer, TeamNum);
    if (StartSpot == None)
    {
        Super.RestartPlayer(aPlayer);
        return;
    }

    NewPawn = Spawn(PC,,, StartSpot.Location, StartSpot.Rotation);
    if (NewPawn == None)
    {
        Super.RestartPlayer(aPlayer);
        return;
    }
    // Monsters auto-spawn a stock MonsterController in PostBeginPlay -
    // replace it with the player.
    if (NewPawn.Controller != None)
        NewPawn.Controller.Destroy();
    aPlayer.Possess(NewPawn);
    aPlayer.PawnClass = PC;
    aPlayer.PreviousPawnClass = NewPawn.Class;
    NewPawn.Anchor = StartSpot;
    NewPawn.LastStartSpot = PlayerStart(StartSpot);
    NewPawn.LastStartTime = Level.TimeSeconds;
    if (PlayerController(aPlayer) != None)
        PlayerController(aPlayer).TimeMargin = -0.1;
    aPlayer.ClientSetRotation(NewPawn.Rotation);
    ApplyInfectedStats(NewPawn, Tier);
}

function ApplyInfectedStats(Pawn P, int Tier)
{
    if (P == None)
        return;
    P.HealthMax = P.default.HealthMax + 40 * Tier;
    P.Health = P.HealthMax;
    P.GroundSpeed = P.default.GroundSpeed + 30 * Tier;
}

// Nearest living human (team 0) pawn to the infected monster.
function Pawn FindNearestHuman(Pawn Self, float MaxDist)
{
    local Pawn Best;
    local float bd, d;
    local Controller C;

    bd = MaxDist;
    for (C = Level.ControllerList; C != None; C = C.NextController)
    {
        if (C.Pawn == None || C.Pawn.Health <= 0 || C.Pawn.bDeleteMe)
            continue;
        if (C.PlayerReplicationInfo == None || C.PlayerReplicationInfo.Team == None)
            continue;
        if (C.PlayerReplicationInfo.Team.TeamIndex != 0)
            continue;
        if (C.PlayerReplicationInfo.bOnlySpectator)
            continue;
        d = VSize(C.Pawn.Location - Self.Location);
        if (d < bd)
        {
            bd = d;
            Best = C.Pawn;
        }
    }
    return Best;
}

//==============================================================================
// Horde damage scaling (horde monsters hit harder than the player horde)
//==============================================================================

function int ReduceDamage(int Damage, pawn injured, pawn instigatedBy, vector HitLocation, out vector Momentum, class<DamageType> DamageType)
{
    local InfectionMonsterController C;

    if (instigatedBy != None)
    {
        C = InfectionMonsterController(instigatedBy.Controller);
        if (C != None)
            Damage += HordeDamageBonus;
    }
    return Super.ReduceDamage(Damage, injured, instigatedBy, HitLocation, Momentum, DamageType);
}

//==============================================================================
// Combat events
//==============================================================================

function Killed(Controller Killer, Controller Killed, Pawn KilledPawn, class<DamageType> damageType)
{
    // A human died: they join the horde (if a round is running).
    if (Killed != None && Killed.bIsPlayer && Killed.PlayerReplicationInfo != None
        && Killed.PlayerReplicationInfo.Team != None
        && Killed.PlayerReplicationInfo.Team.TeamIndex == 0
        && !IsInfected(Killed) && Phase == PHASE_FIGHT)
    {
        if (Killer != None && IsInfected(Killer))
            AddInfectionPoints(Killer, PointsForKill);
        ConvertToInfected(Killed);
    }

    Super.Killed(Killer, Killed, KilledPawn, damageType);
}

function ScoreKill(Controller Killer, Controller Other)
{
    Super.ScoreKill(Killer, Other);
    // Human kills on infected score for the human team. (Infected evolution
    // points are awarded in Killed() so suicides/environmental deaths count.)
    if (Killer == None || Other == None || !Killer.bIsPlayer || !Other.bIsPlayer)
        return;
    if (!IsInfected(Killer) && IsInfected(Other))
        TeamScoreEvent(0, 1, "infection_frag");
}

//==============================================================================
// Per-second supervision (driven by SkaarjInfectionDriver)
//==============================================================================

function int HumansAlive()
{
    local int n;
    local Controller C;

    for (C = Level.ControllerList; C != None; C = C.NextController)
    {
        if (C.Pawn == None || C.Pawn.Health <= 0 || C.Pawn.bDeleteMe)
            continue;
        if (C.PlayerReplicationInfo == None || C.PlayerReplicationInfo.Team == None)
            continue;
        if (C.PlayerReplicationInfo.Team.TeamIndex != 0)
            continue;
        if (C.PlayerReplicationInfo.bOnlySpectator)
            continue;
        n++;
    }
    return n;
}

function CleanupStaleInfected()
{
    local int i;
    for (i = InfectedList.Length - 1; i >= 0; i--)
    {
        if (InfectedList[i] == None || InfectedList[i].PlayerReplicationInfo == None
            || InfectedList[i].PlayerReplicationInfo.bOnlySpectator)
        {
            InfectedList.Remove(i, 1);
            InfectedPoints.Remove(i, 1);
            InfectedTier.Remove(i, 1);
        }
    }
}

function RoundTick()
{
    local int Humans;

    CleanupStaleInfected();
    CleanupHorde();

    if (Phase == PHASE_FIGHT)
    {
        PhaseClock = PhaseClock + 1.0;

        // The horde closes in while humans are alive - pause during
        // intermission/result so the next round starts fresh.
        if (!bHordePaused)
        {
            HordeClock = HordeClock + 1.0;
            if (HordeClock >= HordeInterval)
            {
                HordeClock = 0;
                SpawnHordeWave();
            }
            // keep horde monsters pointed at the nearest human
            RefreshHordeGrudges();
        }

        Humans = HumansAlive();
        if (Humans == 0)
        {
            EndRound(2, false);   // infected win
            return;
        }
        if (Humans == 1 && !bLastHumanWarned)
        {
            bLastHumanWarned = true;
            Broadcast(Self, "ONE HUMAN LEFT - THE HORDE CLOSES IN!", 'CriticalEvent');
        }
        if (RoundTimeLimit > 0 && PhaseClock >= RoundTimeLimit)
            EndRound(1, true);    // humans win on time
    }
    else if (Phase == PHASE_RESULT)
    {
        bHordePaused = true;
        PhaseClock = PhaseClock + 1.0;
        if (PhaseClock >= ResultTime)
        {
            if (bMatchupOver)
            {
                Phase = PHASE_INTERMISSION;
                PhaseClock = 0;
                Broadcast(Self, "MATCHUP " $ MatchupNumber $ " FINAL: HUMANS " $ RoundWins[0]
                    $ "-" $ RoundWins[1] $ " INFECTED", 'CriticalEvent');
            }
            else
                StartRound();
        }
    }
    else if (Phase == PHASE_INTERMISSION)
    {
        PhaseClock = PhaseClock + 1.0;
        if (PhaseClock >= IntermissionTime)
            StartNewMatchup();
    }
}

function RefreshHordeGrudges()
{
    local int i;
    local InfectionMonsterController C;
    local Pawn T;

    for (i = 0; i < HordeMonsters.Length; i++)
    {
        if (HordeMonsters[i] == None || HordeMonsters[i].Health <= 0 || HordeMonsters[i].bDeleteMe)
            continue;
        C = InfectionMonsterController(HordeMonsters[i].Controller);
        if (C == None)
            continue;
        T = FindNearestHuman(HordeMonsters[i], 99999);
        if (T != None)
            C.SetGrudge(T);
    }
}

//==============================================================================
// Round flow
//==============================================================================

function EndRound(int Winner, optional bool bTimedOut)
{
    local string Msg;

    if (Phase != PHASE_FIGHT)
        return;
    Phase = PHASE_RESULT;
    PhaseClock = 0;

    if (Winner == 1)
    {
        RoundWins[0]++;
        TotalWins[0]++;
        if (bTimedOut)
            Msg = "TIME! HUMANITY SURVIVES ROUND " $ RoundNumber $ "!";
        else
            Msg = "HUMANITY WINS ROUND " $ RoundNumber $ "!";
    }
    else
    {
        RoundWins[1]++;
        TotalWins[1]++;
        Msg = "THE INFECTION CONSUMES EVERYONE - ROUND " $ RoundNumber $ " TO THE HORDE!";
    }
    Broadcast(Self, Msg, 'CriticalEvent');
    Broadcast(Self, "MATCH SCORE: HUMANS " $ RoundWins[0] $ "-" $ RoundWins[1] $ " INFECTED", 'CriticalEvent');
    log("SkaarjInfection: round " $ RoundNumber $ " -> winner " $ Winner, 'SkaarjInfectionV1');

    RoundNumber++;
    if (RoundWins[0] > RoundsPerMatch / 2 || RoundWins[1] > RoundsPerMatch / 2)
        bMatchupOver = true;
}

// Everyone returns to humanity for the next round.
function CureEveryone()
{
    local int i;
    local Controller C;

    if (InfectedList.Length == 0)
        return;
    for (i = 0; i < InfectedList.Length; i++)
    {
        C = InfectedList[i];
        if (C == None || C.PlayerReplicationInfo == None)
            continue;
        // kill their monster pawn through the normal death flow so the
        // controller transitions cleanly, then respawn them as humans
        if (C.Pawn != None && C.Pawn.Health > 0 && !C.Pawn.bDeleteMe)
            C.Pawn.KilledBy(C.Pawn);
        // NOTE: NEVER set PawnClass=None - the stock spawner would then
        // try the abstract Engine.Pawn (from the URL Class option) and
        // fail forever with 'Couldn't spawn player of type None'.
        C.PawnClass = class'XGame.xPawn';
        ChangeTeam(C, 0, false);
    }
    InfectedList.Length = 0;
    InfectedPoints.Length = 0;
    InfectedTier.Length = 0;
    Broadcast(Self, "THE INFECTION RECEDES - EVERYONE IS HUMAN AGAIN!", 'CriticalEvent');
}

defaultproperties
{
     GameName="Skaarj Infection"
     Description="Asymmetric infection: die as a human, come back as a monster. Evolve from Pupae to WarLord by eating the survivors!"
     Acronym="INF"
     MapPrefix="DM"
     MapListType="SkaarjInfectionV1.MapListSkaarjInfection"
     HUDType="XInterface.HudCTeamDeathMatch"

     RoundTimeLimit=240
     RoundsPerMatch=3
     PointsForKill=2
     EvolveAt(0)=0
     EvolveAt(1)=2
     EvolveAt(2)=5
     EvolveAt(3)=9
     EvolveAt(4)=14
     ResultTime=5.000000
     IntermissionTime=8.000000
     HordeMax=8
     HordeInterval=12.000000
     HordeHealthBonus=20
     HordeDamageBonus=2
     bAllowBehindView=True
     bBalanceTeams=True
     bPlayersBalanceTeams=True
     PlayerControllerClassName="SkaarjInfectionV1.InfectionPlayerController"
}
