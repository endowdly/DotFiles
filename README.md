# DotFiles

endowdly's dotfiles

## What

This module is a simple tool to sync dotfiles on your filesystem.
It can be used across multiple machines (best on Win10).

Use at your own risk.

## Usage

Import the module and use `Invoke-DotFileSync` and `Invoke-DotCommandSync`.

To save your current (in-place or standing files), use `Backup-DotFiles`.
If you sync a bad dotfile, replace the standing files with `Restore-DotFiles`.
When you use a Sync command the module does not backup for you, **you must manually back your dots up**. 
_This behavior is under-review and may change_.

## Installation

<!-- Note-- Think about removing scoop support -->

### Scoop

Add `endo-bucket` to your buckets:

```powershell
````

### PowerShell Gallery

```powershell
````

## Where? 

This module stores your files in its configured path.
Dotfiles, Backups, and commands (if any) will be stored in the `.dotfiles` directory.

## Using the Config File

The config file lets you control where the manifest file, the archive file, and backups file reside.
Entries in the configuration file must be strings.

The configuration file is validated and only allows three top-level keys:

1. `ManifestFilePath `
2. `ArhiveFilePath`
3. `BackupFilePath`

These keys are self explanatory; you should use paths that can be resolved to valid locations.
The files do not have to exist.

There are three _get_ cmdlets and three _set_ cmdlets for each of these paths--

`(Get|Set)-(Manifest|Archive|Backup)FilePath`

These cmdlets will _get_ and _set_ the module variables that tell other cmdlets where to look.
The cmdlets do not save variables to configuration, _but this will be implemented in the future_.

## Creating a manifest

In order to save your dotfiles, you need to save them to a manifest file.
_Will add the ability to load the manifest into memory and manipulate it directly; adding and removing entries._

```powershell
@(
    New-DotFilesEntry -Source $FilePath
    Get-ChildItem PowerShell -Filter *ps*1 | Foreach-Object FullName | New-DotFilesEntry
) | Export-DotFilesManifest
```

Once the manifest file is made, you can execute the main module functions.
