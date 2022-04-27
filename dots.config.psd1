@{
    PathVariable = @{
        PowerShellCurrentUser = 'Split-Path $Profile.CurrentUserAllHosts'
        # ScoopedCode           = 'Convert-Path $env:USERPROFILE\scoop\apps\vscode\current\data\user-data\User'
    }

    Path = @( 
        # VSCode
        '"$env:APPDATA\Code\User\settings.json"'
        '"$env:APPDATA\Code\User\keybindings.json"'
        '"$env:APPDATA\Code\User\snippets\${env:USERNAME}.code-snippets"'   
        # '"$ScoopedCode\settings.json"'
        # '"$ScoopedCode\keybindings.json"'
        # '"$ScoopedCode\snippets\${env:USERNAME}.code-snippets.json"'
        
        # Alacritty
        '"$env:APPDATA\alacritty\alacritty.yml"'

        # Windows Terminal
        '"$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"'

        # PowerShell
        '"$PowerShellCurrentUser\profile.ps1"'
        '"$PowerShellCurrentUser\profile.psm1"'
        '"$PowerShellCurrentUser\profile.config.psd1"'
        '"$PowerShellCurrentUser\psreadline.ps1"'
        '"$PowerShellCurrentUser\prompt.ps1"'
        '"$PowerShellCurrentUser\argumentcompleter.ps1"'

        # Workspacer Stuff
        '"$home\.workspacer\workspacer.config.csx"'

        # GoPS
        '"$home\.gops"'
        
        # Grafx2
        '"$env:APPDATA\GrafX2\gfx2-win32.cfg"'
        '"$env:APPDATA\GrafX2\gfx2.ini"'
    )

    Command      = @(
        
        # Visual Studio Code
        @{
            Description = 'Install Visual Studio Code Extensions'
            Push  = 'code --list-extensions --show-versions'
            Pull     = 'write-verbose "installing vscode extension $_"; code --install-extension $_'
        } 
        # Scoop
        @{
            Description = 'Add endo-scoop bucket to scoop'
            Push   = ''
            Pull     = 'scoop bucket add endo-scoop https://github.com/endowdly/endo-scoop.git'
        }
        @{
            Description = 'Install scoop apps'
            Push   = 'scoop export'
            Pull     = 'scoop install $_'
        }
    )
}
