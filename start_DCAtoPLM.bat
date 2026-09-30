@echo off
setlocal

title DCAtoPLM

echo ============================================
echo  Criacao de item com PDF no Teamcenter
echo ============================================
echo.

set "SOURCE_CODE="
set /p "SOURCE_CODE=Digite o codigo do item: "

if not defined SOURCE_CODE (
    echo.
    echo Nenhum codigo foi informado.
    echo.
    pause
    exit /b 1
)

echo.

set "ITEM_NAME="
set /p "ITEM_NAME=Digite o nome do item: "

if not defined ITEM_NAME (
    echo.
    echo Nenhum nome foi informado.
    echo.
    pause
    exit /b 1
)

set "SOURCE_CODE=%SOURCE_CODE:"=%"
set "ITEM_NAME=%ITEM_NAME:"=%"

echo.
echo Codigo: %SOURCE_CODE%
echo Nome: %ITEM_NAME%
echo.

powershell.exe ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%~dp0import_dcaPdfToTeamcenter.ps1" ^
    -SourceCode "%SOURCE_CODE%" ^
    -ItemName "%ITEM_NAME%" ^
    -SearchRoot "C:\DCA"

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