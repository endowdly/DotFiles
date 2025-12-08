# DotFiles

<!-- markdownlint-disable MD024 -->

endowdly's dotfiles

## What

This module is a simple tool to sync dotfiles on your filesystem.
It can be used across multiple machines (best on Win10)--
all you need is your dots.manifest` and your dots directory. 

Use at your own risk.

## Usage

Import the module and use `Invoke-DotFileSync` and `Invoke-DotCommandSync`.

To save your current (in-place or standing files), use `Backup-Dots`.
If you sync a bad dotfile, replace the standing files with `Restore-Dots`.
When you use a Sync command the module does not backup for you, **you must manually backup your dots**. 

## Installation

### Scoop

Add `endo-bucket` to your buckets:

```powershell
````

### PowerShell Gallery

```powershell
````

## Where? 

This module stores your files in its path.
Synced dotfiles and commands (if any) will be stored in the `dots` directory.
Backups (if any) will be stored in the `backup` directory.

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

When compressing dotfiles using `pushToArchive.cmd` or running `.\dots.ps1 push`, files in this list that do not exist are _skipped_ and not loaded or saved.
Afterwards, when expanding dotfiles using `pullFromArchive.cmd` or running `.\dots.ps1 pull [-force]`, files in this list are ignored.
Only files saved in the `dots.xml` will be pulled.

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

This is a hashtable array that allows you specify three properties:

1. Pull
2. Push
3. Description

Each hashtable entered is validated and can only contain the above keys.

The hashtables can contain only `Push` _or_ `Pull` commands.
The `Description` key will be used for easy identification and selection.
It should be noted that commands must include a `Pull` command but do not need a `Push` Command.

When pushing dotfiles each item will save the content of its evaluation to a tagged file.
When pull commands, **if the item has content**, it will execute its `Pull` command on **each item in its contents**.
If it has no content, it will simply execute the command and return its evaluation, if any.

#### Example

```powershell
Commands = @(
    @{
        Description = 'Install Scoop Apps'
        Push = 'scoop export'
        Pull = 'scoop install $_'
    }
)
```

This hashtable will set the contents of the `scoop export` command to a file.
On pull, every line of content will be run through `scoop install`.
