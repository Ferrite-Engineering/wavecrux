@echo off
REM Windows companion to build_test_plugins.sh.
REM
REM Builds every decoder-plugin loader test fixture into a .dll
REM alongside its source. Requires MSVC `cl.exe` (Developer Command
REM Prompt) or a compatible compiler in $PATH.

setlocal enabledelayedexpansion

set "HERE=%~dp0"
set "INCLUDE_DIR=%HERE%..\..\..\include"

where cl.exe >NUL 2>&1
if errorlevel 1 (
    echo build_test_plugins.bat: cl.exe not found; install MSVC build tools 1>&2
    exit /b 1
)

call :build test_plugin                 test_passthrough        || exit /b 1
call :build test_plugin_abi_mismatch    test_abi_mismatch       || exit /b 1
call :build test_plugin_missing_symbol  test_missing_symbol     || exit /b 1
call :build test_plugin_corrupt_manifest test_corrupt_manifest  || exit /b 1
call :build test_plugin_named           test_named              || exit /b 1
call :build test_plugin_config          test_config             || exit /b 1
call :build test_plugin_lifecycle       test_lifecycle          || exit /b 1
call :build test_plugin_width           test_width              || exit /b 1

echo all decoder-plugin test fixtures built
exit /b 0

:build
set "SUBDIR=%~1"
set "LIBNAME=%~2"
REM Output keeps the `lib` prefix to match build_test_plugins.sh and the
REM names the Dart loader + _stageDirectory expect uniformly across
REM platforms (libtest_passthrough.dll, etc.). Without it the staging step
REM throws "missing pre-built fixture" when cl.exe is actually present.
cl.exe /nologo /LD /I "%INCLUDE_DIR%" ^
    "%HERE%%SUBDIR%\test_plugin.c" ^
    /Fe:"%HERE%%SUBDIR%\lib%LIBNAME%.dll" >NUL
exit /b %errorlevel%
