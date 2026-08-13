@echo off
:10
ucc server DM-Rankin?game=SkaarjInfectionV1.SkaarjInfectionGame?Mutator=ServerBrowserGametypeOverrideV1.MutServerBrowserGametypeOverride -ini=UT2004SkaarjInfection.ini -log=SkaarjInfection_server.log
copy SkaarjInfection_server.log SkaarjInfection_servercrash.log
goto 10
