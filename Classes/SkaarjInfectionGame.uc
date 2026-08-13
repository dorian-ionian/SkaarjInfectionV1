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

    log("SkaarjInfection: init - round " $ RoundTimeLimit $ "s best of " $ RoundsPerMatch, 'SkaarjInfectionV1');
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
    CureEveryone();   // no-one carries infection into the next round
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

    if (Phase == PHASE_FIGHT)
    {
        PhaseClock = PhaseClock + 1.0;
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
        C.PawnClass = None;
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
     bBalanceTeams=True
     bPlayersBalanceTeams=True
}
