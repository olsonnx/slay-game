@echo off
python "%~dp0tools\launch_lighting_lab.py" %*
if errorlevel 1 pause
