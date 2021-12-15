@echo off
echo 'Starting dotfile push...'

powershell /noprofile /nologo /executionpolicy bypass /command "& .\dots.ps1 push both -select -force"
pause