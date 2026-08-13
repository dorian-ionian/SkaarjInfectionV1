//=============================================================================
// SkaarjInfectionDriver
// A dedicated 1s timer actor that drives the round logic independently of
// the game's state machine and force-starts the match when the stock
// PendingMatch never does (e.g. zero humans on a dedicated server).
//=============================================================================
class SkaarjInfectionDriver extends Info;

var SkaarjInfectionGame Game;
var int StartupClock;
var bool bForcedStart;

simulated function PostBeginPlay()
{
    Super.PostBeginPlay();
    if (Role == ROLE_Authority)
        SetTimer(1.0, true);
}

function Timer()
{
    if (Game == None)
    {
        Game = SkaarjInfectionGame(Level.Game);
        if (Game == None)
            return;
    }

    if (!bForcedStart)
    {
        if (Game.bShowStarted)
            bForcedStart = true;
        else
        {
            StartupClock++;
            if (StartupClock >= 8)
            {
                bForcedStart = true;
                log("SkaarjInfectionDriver: forcing match start", 'SkaarjInfectionV1');
                Game.StartMatch();
            }
        }
    }

    Game.RoundTick();
}

defaultproperties
{
}
