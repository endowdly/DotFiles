# DotFiles

<!-- markdownlint-disable MD024 -->

endowdly's dotfiles

Use at your own risk.
Install to your local disk with `restore.cmd`.
Update the dots with `backup.cmd`.
Update the files on disk (if they already exist) with `update.cmd`.

`restore.cmd` will force file creation if a file exists in `dots.xml` but not on the target machine.
`update.cmd` will not force file creation, but will overwrite an existing file.

## Included

dotFile                      | For                | Description                    | Status
-----------------------------|--------------------|--------------------------------|------------
settings.json                | Visual Studio Code | User settings file             | Active
keybindings.json             | Visual Studio Code | User keybindings file          | Active
endowdly.code-snippets.json* | Visual Studio Code | User Snippets file             | Active
extensions.txt               | Visual Studio Code | User extensions list           | Active
alacritty.yaml               | Alacritty          | Alacritty configuration        | Active
Profile.ps1                  | PowerShell         | Profile loader                 | Active
Profile.Config.ps1           | PowerShell         | Profile configuration          | Active
Profile.psm1                 | PowerShell         | Profile custom functions       | Active
PSReadLine.ps1               | PowerShell         | PSReadLine key handlers        | Active
prompt.ps1                   | PowerShell         | PowerShell prompt file         | Active
ArgumentCompleter.ps1        | PowerShell         | ArgumentCompleter file         | Active
settings.json                | Windows Terminal   | Windows Terminal settings file | Semi-Active
scoop.txt                    | scoop              | scoop packages list            | Active
.vimrc                       | neovim/vim         | Vim configuration file         | Semi-Active
keys.vim                     | neovim/vim         | Vim keybindings file           | Semi-Active
general.vim                  | neovim/vim         | Vim General/UI configuration   | Semi-Active
autocommands.vim             | neovim/vim         | Vim Autocommands configuration | Semi-Active
.gops                        | PowerShell/GoPS    | GoPS module jump file          | Active

_* Will replace `endowdly` with the current `USERNAME`_

## Using the Config File

The config file lets you control what dotfiles and setup commands are saved and run.
It also lets you define some variables to access file paths.
This helps to ensure the correct paths are being stored and saved when dotfiles are pushed/pulled across multiple machines.

Entries in the configuration file must be strings.
But it is important to know that each string is cast and invoked as a scriptblock.
This means any command or variable that is entered **will be expanded and executed**.
This is probably a little dangerous: if you are not careful with what commands you enter, you could mess up your machine.

The configuration file is validated and only allows three top-level keys:

1. PathVariable
2. Path
3. Command

Let's take a look at each and see what the sections can do.

### PathVariable

This is a hashtable that allows you to define variables the other sections of the configuration file can use.
The hashtable key will become the variable name and the variable value will be the result of the hashtable value evaluated in a child scope.

The configuration values will be run in an unrestricted, noprofile session of PowerShell.
All built-in commands, automatic variables, and environmental variables should be available.

#### Example

```powershell
PathVariable = @{
    PowerShellCurrentUser = 'Split-Path $Profile.CurrentUserAllHosts'
}
```

This will set `$PowerShellCurrentUser` to the evaluation of `Split-Path $Profile.CurrentUserAllHosts`.
If this executes in the normal environment, this should evaluate to a string containing the full path of the parent directory of the current user's profile (`Profile.ps1`).
`$PowerShellCurrentUser` will be valid for use in the `Path` and `Command` sections of the configuration file.

### Path

This is a string array that allows you to specify what paths you'd like to import and export to.
These should evaluate to a full path that is a valid path location (but does not have to exist).
Environmental and automatic variables, and variables defined in the `PathVariable` section, are handy here.

When compressing dotfiles using `backup.cmd` or running `.\dots.ps1 backup`, files in this list that do not exist are _skipped_ and not loaded or saved.
Afterwards, when expanding dotfiles using `update.cmd`, `restore.cmd` or running `.\dots.ps1 update [-force]`, files in this list are ignored.
Only files saved in the `dots.xml` will be pushed.

#### Example

```powershell
Path = @(
    # Using the previously declared variable
    '"$PowerShellCurrentUser\profile.ps1"'

    # Using an environmental variable
    '"$env:USERPROFILE\.vimrc"'

    # You can just use a full path too
    'C:\Users\you\path\to\something.txt' 
)
```

Remember two things are true: all entries must be strings that, when run in a scriptblock, evaluate to a string.
This is why you see the quoting in the example.

### Command

This is a hashtable array that allows you specify two commands:

1. Compress
2. Expand

Each hashtable entered is validated and can only contain the above keys.

The hashtables can contain only `Compress` _or_ `Expand` commands.
It should be noted that _Compress_ only commands have little to no utility while `Expand` only commands may have some.

When compressing dotfiles using `backup.cmd` or running `.\dots.ps1 backup`, each item will set its content to the evaluation of its `Compress` command.
When expanding dotfiles using `update.cmd`, `restore.cmd`, or running `.\dots.ps1 update [-force]`, **if the item has content**, it will execute its `Expand` command on **each item in its content**.
If it has no content, it will simply execute the command and return its evaluation, if any.

#### Example

```powershell
Commands = @(
    @{
        Compress = 'scoop export'
        Expand   = 'scoop install $_'
    }
)
```

This hashtable will set the contents of the `scoop export` command to an entry in `dots.xml` when compressed.
On expansion, every line of content will be run through `scoop install`.

## Using the dots.ps1 script

You should not need to alter or mess with `dots.ps1`.
If you want to call `dots.ps1` in PowerShell instead of using the included command files, here is a table:

I want to run... | In PowerShell, run...
-----------------|---------------------------
`backup.cmd`     | `.\dots.ps1 backup`
`update.cmd`     | `.\dots.ps1 update`
`restore.cmd`    | `.\dots.ps1 update -force`
