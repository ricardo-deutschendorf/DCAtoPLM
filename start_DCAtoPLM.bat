@echo off
setlocal

title DCAtoPLM

if exist "%~dp0.env" (
    for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%~dp0.env") do (
        if not "%%A"=="" set "%%A=%%B"
    )
) else if exist "%~dp0DCAtoPLM.local.bat" (
    call "%~dp0DCAtoPLM.local.bat"
)

powershell.exe ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%~dp0import_dcaPdfToTeamcenter.ps1"

set "EXIT_CODE=%ERRORLEVEL%"

echo.

if not "%EXIT_CODE%"=="0" (
    echo O processo terminou com erro.
) else (
    echo O processo foi concluido.
)

echo.
pause

endlocal
exit /b %EXIT_CODE%