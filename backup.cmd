@echo off
echo 'Starting dotfile pull...'

powershell /noprofile /nologo /executionpolicy bypass /command "& .\dots.ps1 backup"
pause