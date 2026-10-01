@echo off
setlocal

title DCAtoPLM

powershell.exe ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%~dp0import_dcaPdfToTeamcenter.ps1" ^
    -SearchRoot "C:\VAULT_ROOT"

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