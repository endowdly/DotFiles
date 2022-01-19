@{
    PathVariable = @{
        PowerShellCurrentUser = 'Split-Path $Profile.CurrentUserAllHosts'
    }

    Path          = @( 
        # VSCode
        '"$env:APPDATA\Code\User\settings.json"'
        '"$env:APPDATA\Code\User\snippets\${env:USERNAME}.code-snippets"'

        # Alacritty
        '"$env:APPDATA\alacritty\alacritty.yml"'

        # PowerShell
        '"$PowerShellCurrentUser\profile.ps1"'
        '"$PowerShellCurrentUser\profile.psm1"'
        '"$PowerShellCurrentUser\profile.config.psd1"'
        '"$PowerShellCurrentUser\psreadline.ps1"'
        '"$PowerShellCurrentUser\prompt.ps1"'
        '"$PowerShellCurrentUser\argumentcompleter.ps1"'

        # GoPS
        '"$home\.gops"'
        
        # Windows Terminal
        '"$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"'
        
        # Vim
        '"$env:USERPROFILE\.vimrc"'
        '"$env:USERPROFILE\.vim\general.vim"'
        '"$env:USERPROFILE\.vim\keys.vim"'
        '"$env:USERPROFILE\.vim\autocommands.vim"'

        # Grafx2
        '"$env:APPDATA\GrafX2\gfx2-win32.cfg"'
        '"$env:APPDATA\GrafX2\gfx2.ini"'
    ) 

    Command       = @(
        # Visual Studio Code
        @{
            Description = 'Install Visual Studio Code Extensions'
            Compress = 'code --list-extensions --show-versions'
            Expand   = 'Write-Verbose "Installing Code Extension: $_"; code --install-extension $_'
        } 

        # Scoop
        @{
            Description = 'Add endo-scoop bucket to scoop'
            Compress = ''
            Expand   = 'scoop bucket add endo-scoop https://github.com/endowdly/endo-scoop.git'
        }
        @{
            Description = 'Install scoop apps'
            Compress = 'scoop export'
            Expand   = 'scoop install $_'
        }
    )
}
