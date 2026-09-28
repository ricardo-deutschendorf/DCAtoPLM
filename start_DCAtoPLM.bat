@echo off
setlocal

echo ============================================
echo  Criacao de item com PDF no Teamcenter
echo ============================================
echo.

set "SOURCE_CODE="
set /p SOURCE_CODE="Digite o codigo do item: "

if not defined SOURCE_CODE (
    echo.
    echo Nenhum codigo foi informado.
    pause
    exit /b 1
)

echo.

set "PDF_PATH="
set /p PDF_PATH="Digite ou arraste o PDF para esta janela: "

if not defined PDF_PATH (
    echo.
    echo Nenhum PDF foi informado.
    pause
    exit /b 1
)

set "SOURCE_CODE=%SOURCE_CODE:"=%"
set "PDF_PATH=%PDF_PATH:"=%"

echo.
echo Codigo: %SOURCE_CODE%
echo PDF: %PDF_PATH%
echo.

powershell.exe ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%~dp0import_dcaPdfToTeamcenter.ps1" ^
    -SourceCode "%SOURCE_CODE%" ^
    -PdfPath "%PDF_PATH%"

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