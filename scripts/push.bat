@echo off
echo Pushing files from mirror to original...
echo Source: %USERPROFILE%\PRJ\MSSTLITE-MIRROR\msst-lite-znuny-mirror
echo Destination: %USERPROFILE%\PRJ\MSSTLITE\msst-lite-znuny
echo.
robocopy "%USERPROFILE%\PRJ\MSSTLITE-MIRROR\msst-lite-znuny-mirror" "%USERPROFILE%\PRJ\MSSTLITE\msst-lite-znuny" /MIR /XD .git scripts
echo.
echo Done!
pause
