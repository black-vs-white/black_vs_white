@echo off

pushd "%~dp0\.."

set OUT_DIR=build\release
if not exist %OUT_DIR% mkdir %OUT_DIR%

SET "_ALLOW_CONFIG_OVERRIDE=%ALLOW_CONFIG_OVERRIDE%"
IF NOT DEFINED _ALLOW_CONFIG_OVERRIDE SET "_ALLOW_CONFIG_OVERRIDE=false"

odin.exe build src\main_desktop -subsystem:windows ^
                     -define:ALLOW_CONFIG_OVERRIDE=%_ALLOW_CONFIG_OVERRIDE% ^
                     -vet -vet-packages:main ^
                     -collection:sol=extern/sol ^
                     -linker:radlink -strict-style -out:%OUT_DIR%\black_vs_white.exe

IF %ERRORLEVEL% NEQ 0 exit /b 1

xcopy /y /e /i assets %OUT_DIR%\assets >nul
IF %ERRORLEVEL% NEQ 0 exit /b 1

echo Desktop build created in %OUT_DIR%

popd