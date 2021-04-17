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
        
        # Windows Terminal
        '"$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"'
        
        # Vim
        '"$env:USERPROFILE\.vimrc"'
        '"$env:USERPROFILE\.vim\general.vim"'
        '"$env:USERPROFILE\.vim\keys.vim"'
        '"$env:USERPROFILE\.vim\autocommands.vim"'
    ) 

    Command       = @(
        # Visual Studio Code
        @{
            Compress = 'code --list-extensions --show-versions'
            # Expand   = 'write-verbose "code extension install, this is silent"; code --install-extension $_'
        } 

        # Scoop
        @{
            Compress = 'scoop export'
            Expand   = 'scoop install $_'
        }
    )
}