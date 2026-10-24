@echo off
python "%~dp0tools\event-editor\launch.py" %*
if errorlevel 1 pause
