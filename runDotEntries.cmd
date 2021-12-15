@echo off
echo 'Starting dotfile pull and running entry selections...'

powershell /noprofile /nologo /executionpolicy bypass /command "& .\dots.ps1 pull entry -select"
pause