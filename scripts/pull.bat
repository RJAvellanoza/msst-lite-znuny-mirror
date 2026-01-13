@echo off
echo Pulling files from original to mirror...
echo Source: %USERPROFILE%\PRJ\MSSTLITE\msst-lite-znuny
echo Destination: %USERPROFILE%\PRJ\MSSTLITE\msst-lite-znuny-mirror
echo.
robocopy "%USERPROFILE%\PRJ\MSSTLITE\msst-lite-znuny" "%USERPROFILE%\PRJ\MSSTLITE\msst-lite-znuny-mirror" /MIR /XD .git
echo.
echo Done!
pause
