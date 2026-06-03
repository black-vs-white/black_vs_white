@echo off

pushd "%~dp0\.."

set OUT_DIR=build\debug
if not exist %OUT_DIR% mkdir %OUT_DIR%

odin.exe build src\main_desktop -subsystem:console -debug ^
                     -vet -vet-packages:main ^
                     -define:STA_FILTER_STDLIB=false ^
                     -collection:sol=extern\sol ^
                     -strict-style -out:%OUT_DIR%\black_vs_white.exe
if %ERRORLEVEL% NEQ 0 exit /b 1
echo Desktop build created in %OUT_DIR%

popd