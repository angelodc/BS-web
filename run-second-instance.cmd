@echo off
rem Abre uma segunda instancia do jogo para testar multiplayer local.
rem Ajuste GODOT_EXE se o executavel nao estiver no Downloads do usuario atual.
if not defined GODOT_EXE set "GODOT_EXE=%USERPROFILE%\Downloads\Godot_v3.4.4-stable_win64.exe\Godot_v3.4.4-stable_win64.exe"
set BS_WINDOWED=1
start "" "%GODOT_EXE%" --path "%~dp0." --position 220,140
