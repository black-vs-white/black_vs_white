@echo off

pushd "%~dp0\.."

cargo run --manifest-path publish/helper/Cargo.toml -- ^
    -a assets/ATTRIBUTIONS.txt ^
    -o publish/GENERATED.html ^
    publish/DISCLAIMER.md ^
    publish/DESCRIPTION.md

popd