@echo off
setlocal DisableDelayedExpansion
agency copilot %*
set "exitCode=%ERRORLEVEL%"
endlocal & exit /b %exitCode%
