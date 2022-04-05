using namespace System.IO
using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.Management.Automation

param(

)

#region Data and Literals ------------------------------------------------------
data Setting {
    @{
        ErrorActionPreference = 'Continue'
        VerbosePreference     = 'Continue'
        ConfigFile            = 'dots.config.psd1'
        ManifestFile          = 'dots.manifest' 
    }
}

data Message {
    @{
        TerminatingError = @{
            InvalidConfig       = '''{0}'' {1} not a valid config key. Valid keys are: {2}'
            ConfigNotFound      = 'Fatal: config file ''{0}'' not found or invalid!'
            What                = 'Fatal: you somehow reached the unreachable!'
            Wip                 = 'Work in progress: Not implemented yet!'
            NotAManifest        = '''{0}'' is not a valid manifest file!'
            FileHashMismatch    = 'Hash for file ''{0}'' does not match manifest!'
            CommandHashMismatch = 'Hash for command ''{0}'' does not match manifest!'
        }
        ShouldProcess    = @{
            ExportDotFile = 'Overwrite dot file archive'
        }
        ShouldContinue   = @{
            SyncDotFiles = @{
                Query   = 'There {0} {1} file{2} to push and {3} file{4} to pull. Sync?'
                Caption = 'Sync Dot Files'
            }
            UpdateDotFiles = @{
                Query = 'This will push and overwrite {0} files to the dot archive from the local computer. Continue?'
                Caption = 'Update Dot Files in Dots'
            } 
            UpdateLocalFiles = @{
                Query = 'This will pull and overwrite {0} files from the dot archive to local computer. Continue?'
                Caption = 'Update Local Files with Dots'
            }
            UpdateDotManifest = @{
                Query = 'Overwrite the dot manifest with the current configuration data?'
                Caption = 'Update Dot Manifest with current configuration'
            }
            SaveDotCommands = @{
                Query = 'Save {0} commands data to the archive?'
                Caption = 'Save dot commands from current configuration'
            }
            InvokeDotCommands = @{
                Query = 'Run {0} commands? Some may use data in the archive.'
                Caption = 'Invoke dot commands'
            }
        }      
       
        Choice           = @{
            Common               = @{
                Update = '&Update'
                Exit   = 'E&xit'

            }
            InvokeDotFileSync    = @{
                Sync = '&Sync'
                Pull = 'Pu&ll'
                Push = 'Pus&h'
            }
            InvokeDotCommandSync = @{
                Save   = '&Save'
                Invoke = '&Invoke'
            }
        }
        HelpMessage      = @{
            Common               = @{
                Update = 'Update the dot manifest with the current configuration'
                Exit   = 'Does nothing and quits the cmdlet'
            }
            InvokeDotFileSync    = @{
                Sync = 'Push newer local files and pull newer dot files'
                Pull = 'Pull dot files and overwrite local files'
                Push = 'Push local files and overwrite dot files'
            }
            InvokeDotCommandSync = @{
                Save   = 'Saves the output of the commands in the manifest file'
                Invoke = 'Invokes the commands with the data in the archive, if any'
            }
        }

        PromptForChoice  = @{
            InvokeDotFileSync    = @{
                ChoiceCaption = 'How do you want to sync the dot files?'
                ChoiceMessage = 'Dot File Sync'
            }
            InvokeDotCommandSync = @{
                ChoiceCaption = 'How do you want to sync commands?'
                ChoiceMessage = 'Dot Command Sync'
            }
        } 

        Warning = @{
            NoManifestFile = 'No manifest file found. Run `Update-DotManifest` to create data for push.'
        }
    }
}

data Directory {
    @{
        Dots   = 'dots'
        Backup = 'backup'
    }
}

data ConfigValidation {
    'PathVariable'
    'Path'
    'Command'
}

data ConfigCommandValidation {
    'Push'
    'Pull'
    'Description'
}

data IsAre {
    'is'
    'are'
}

data Ess {
    ''
    's'
}

data Literal {
    @{
        Empty      = ''
        Space      = ' '
        CommaSpace = ', '
        CheckMark  = '-'
        Current    = '>'
        Newline    = "`n"
    }
}

data Formatter {
    @{
        Hex = 'x'
    }
}

#region Config -----------------------------------------------------------------


function Assert-Config ($x, $y) {
    $xs = [HashSet[string]] $x
    $ys = [HashSet[string]] $y

    if (!$xs.IsSubsetOf($ys)) {
        [void] $xs.ExceptWith($ys)

        $isAre = $IsAre[$xs.Count -gt 1]

        throw ($Message.TerminatingError.InvalidConfig -f ($xs -join $Character.CommaSpace),
            $isAre,
            ($ys -join $Character.CommaSpace))
    }
}


try {
    $Config = Import-PowerShellDataFile (Join-Path $PSScriptRoot $Setting.ConfigFile)
    Assert-Config @($Config.Keys) $ConfigValidation
    Assert-Config @($Config.Command.Keys) $ConfigCommandValidation
}
catch {
    Write-Error $_ -ErrorAction Continue
    Write-Error ($Message.TerminatingError.ConfigNotFound -f $ConfigFile.FileName)
}

$DotsDirectory = Join-Path $PSScriptRoot $Directory.Dots
$BackupDirectory = Join-Path $PSScriptRoot $Directory.Backup
$Directory.GetEnumerator().ForEach{
    if (-not(Join-Path $PSScriptRoot $_.Value | Test-Path)) {
        New-Item -ItemType Directory -Name $_.Value -Path $PSScriptRoot
    }
}
#endregion

#region PowerShell Preferences -------------------------------------------------

$ErrorActionPreference = $Setting.ErrorActionPreference
$VerbosePreference = $Setting.VerbosePreference

#endregion


#region Types ------------------------------------------------------------------


enum EntryType {
    File
    Command
}

enum DirectoryChoice {
    Dot
    Backup
}

enum Target {
    Local
    Archive
    Same
}

class Entry {
    [string] $Id
    [EntryType] $Type
    [string] $Target
    [string] $Source
    [string] $FileHash 
}

function New-Entry ($Source, [EntryType] $Type) {
    switch ($Type) {
        File {
            $value = Invoke-Expression $Source

            # Abort -- the path does not exist and there is nothing to push
            if (-not (Test-Path $value)) {
                return
            }

            $id = $value.GetHashCode().ToString($Formatter.Hex)
            $hash = (Get-FileHash $value).Hash
            $target = $source
        }

        Command {

            # Test for a pull command
            if ([string]::IsNullOrWhiteSpace($Source.Pull)) {
                return
            }

            # We can have a naked push command
            $value =
                if ([string]::IsNullOrWhiteSpace($Source.Push)) {
                    $Literal.Empty
                }
                else {
                    $Source.Push
                }
            $id = $Source.Description.GetHashCode().ToString($Formatter.Hex)
            $target = $Source.Pull
            $hash = $Literal.Empty
        }
    }

    [Entry] @{
        Id       = $id
        Type     = $Type
        Target   = $Target
        Source   = $value
        FileHash = $hash
    }
}


class EntryCompare {
    [Entry] $Entry
    [string] $SyncTarget
    [string] $Id
    [string] $Name
    [Target] $Target
}


function Initialize-EntryCompare ($Entry) {
    [EntryCompare] @{
        Entry      = $Entry
        SyncTarget = [string]::Empty
        Id         = $Entry.Id
        Name       = ((Invoke-Expression $Entry.Target) -as [FileInfo]).Name
        Target     = [Target]::Local
    }
}


filter Set-SyncTarget ($Path) {
    $entryCompare = $_
    $targetFile = (Invoke-Expression $entryCompare.Entry.Target) -as [FileInfo]
    $dotFile = Get-ChildItem $Path | Where-Object Name -eq $entryCompare.Entry.Id

    if ($targetFile.LastWriteTime -gt $dotFile.LastWriteTime) {
        $entryCompare.SyncTarget = $targetFile.FullName
        $entryCompare.Target = [Target]::Local
    }
    elseif ($targetFile.LastWriteTime -eq $dotFile.LastWriteTime) {
        $entryCompare.SyncTarget = [string]::Empty
        $entryCompare.Target = [Target]::Same
    }
    else {
        $entryCompare.SyncTarget = $dotFile.FullName
        $entryCompare.Target = [Target]::Archive
    }

    $entryCompare
}


function New-EntryCompare ($Entry, $Path) {
    Initialize-EntryCompare $Entry | Set-SyncTarget $Path
}


#endregion

#region Setup ------------------------------------------------------------------

# Source PathVariables
$Config.PathVariable.GetEnumerator().ForEach{ Set-Variable $_.Key (Invoke-Expression $_.Value) }

# Source Manifest, if it exists
$ManifestFile = Join-Path $PSScriptRoot $Setting.ManifestFile


function New-Scriptblock {
    param(
        [Parameter(ValueFromPipeline)]
        [string[]] $InputObject
    )

    begin {
        $f = {
            [scriptblock]::Create($_)
        }
    }

    process {
        $InputObject.ForEach($f)
    }
}

# Maybe use 'New-' ?
function Get-DotManifest {
    # .Description
    #  Returns an Entry array from configuration file data

    # Source the Path Variables
    $dotFiles = $Config.Path.GetEnumerator().ForEach{ New-Entry $_ File }
    $dotCommand = $Config.Command.GetEnumerator().ForEach{ New-Entry $_ Command }

    $dotFiles + $dotCommand
}


function Get-FileEntry { $input.Where{ $_.Type -eq [EntryType]::File } }
function Get-CommandEntry { $input.Where{ $_.Type -eq [EntryType]::Command } }


filter Export-DotManifest ($Path) {
    if (Test-Path -IsValid $Path) {
        Export-Csv -Path $Path -InputObject $_ -Append
    }
}


function Import-DotManifest ($Path) {
    try {
        [Entry[]] (Import-Csv $Path)
    }
    catch [System.InvalidCastException] {
        Write-Error -ErrorAction Stop -Message ($Message.TerminatingError.NotAManifest -f $Path)
    }
    catch {
        Write-Error $_ -ErrorAction Stop
    }
}


filter Invoke-DotPush ([DirectoryChoice] $To) {
    $path =
    switch ($To) {
        Dot { $DotsDirectory }
        Backup { $BackupDirectory }
    }
    $entry = $_

    switch ($entry.Type) {
        File {
            Copy-Item -Path $entry.Source -Destination (Join-Path $path $entry.Id) -Force
        }

        Command {
            if ([string]::IsNullOrWhiteSpace($entry.Source)) {
                New-Item -ItemType File -Path (Join-Path $path $entry.Id) -Force | Out-Null
            }
            else {
                Invoke-Expression $entry.Source | Out-File (Join-Path $path $entry.Id) -Append -Force
            }
        }
    }
}


filter Invoke-DotPull ([DirectoryChoice] $From) {
    $path =
    switch ($From) {
        Dot { $DotsDirectory }
        Backup { $BackupDirectory }
    }
    $entry = $_

    switch ($entry.Type) {
        File {
            $x = Invoke-Expression $entry.Target
            $y = Join-Path $path $entry.Id
            $z = (Get-FileHash $y).Hash

            if ($z -ne $entry.FileHash) {
                $name = $x -as [FileInfo]

                # Write-Warning ('File: {0} -- Manifest: {1}' -f $z, $entry.FileHash)

                Write-Error ($Message.TerminatingError.FileHashMismatch -f $name) -ErrorAction Stop
            }

            Copy-Item -Path $y -Destination $x -Force -WhatIf
        }

        Command {
            $x = Join-Path $path $entry.Id
            $z = Get-Content $x
            $f = New-Scriptblock $entry.Target
            # $f = New-Scriptblock 'Write-Host $_'

            $z.ForEach($f)
        }
    }
}


function Update-LocalFiles {
    [CmdletBinding()]
    param([switch] $Force)

    if (-not (Test-Path $ManifestFile)) {
        Write-Warning $Message.Warning.NoManifestFile

        return
    }
    
    $files = Import-DotManifest $ManifestFile | Get-FileEntry 

    if ($Force -or $PSCmdlet.ShouldContinue(
        ($Message.ShouldContinue.UpdateLocalFiles.Query -f $files.Count),
        $Message.ShouldContinue.UpdateLocalFiles.Caption)) {
        $files | Invoke-DotPull Dot
    }
}


function Update-DotFiles {
    [CmdletBinding()]
    param([switch] $Force)

    $files = Get-DotManifest | Get-FileEntry

    if ($Force -or $PSCmdlet.ShouldContinue(
        ($Message.ShouldContinue.UpdateDotFiles.Query -f $files.Count),
        $Message.ShouldContinue.UpdateDotFiles.Caption)) {
        $files | Invoke-DotPush Dot
    }
}


function Update-DotManifest {
    [CmdletBinding()]
    param([switch] $Force)

    if ($Force -or $PSCmdlet.ShouldContinue(
        $Message.ShouldContinue.UpdatDotManifest.Query,
        $Message.ShouldContinue.UpdateDotManifest.Caption)) {

        if (Test-Path $ManifestFile) {
            Remove-Item $ManifestFile
        }

        Get-DotManifest | Export-DotManifest $ManifestFile
    }
}


function Invoke-DotCommands {
    [CmdletBinding()]
    param([switch] $Force)

    if  (-not (Test-Path $ManifestFile)) {
        Write-Warning $Message.Warning.NoManifestFile

        return
    }

    $cmds = Import-DotManifest $ManifestFile | Get-CommandEntry

    if ($Force -or $PSCmdlet.ShouldContinue(
        ($Message.ShouldContinue.InvokeDotCommands.Query -f $cmds.Count),
        $Message.ShouldContinue.InvokeDotCommands.Caption)) { 

        $cmds | Invoke-DotPull Dot
    }
}


function Save-DotCommands {
    [CmdletBinding()]
    param([switch] $Force)
    
    $cmds = Get-DotManifest | Get-CommandEntry
    
    if ($Force -or $PSCmdlet.ShouldContinue(
        ($Message.ShouldContinue.SaveDotCommands.Query -f $cmds.Count),
        $Message.ShouldContinue.SaveDotCommands.Caption)) {

        $cmds | Invoke-DotPush Dot
    }
}

filter Get-NewerDot {
    $_ |
    Get-FileEntry |
    Foreach-Object { New-EntryCompare $_ $DotsDirectory }
}


function Get-PushForSync {
    Get-DotManifest |
    Get-NewerDot |
    Where-Object { $_.Target -eq [Target]::Local } |
    ForEach-Object Entry
}


function Get-PullForSync {
    Get-DotManifest |
    Get-NewerDot |
    Where-Object { $_.Target -eq [Target]::Archive } |
    ForEach-Object Entry
}


function New-ChoiceDescription ($s, $s1) {
    New-Object Host.ChoiceDescription $s, $s1
}


function Sync-DotFiles {
    [CmdletBinding()]
    param([switch] $Force)

    begin {
        $push = Get-PushForSync
        $pull = Get-PullForSync
        $v = $IsAre[$push.Count -ne 1]
        $s0 = $Ess[$push.Count -ne 1]
        $s1 = $Ess[$pull.Count -ne 1]
    }

    end {
        if (-not (Test-Path $ManifestFile)) {
            Update-DotManifest -Force:$Force
        }

        if ($Force -or $PSCmdlet.ShouldContinue(
                ($Message.ShouldContinue.SyncDotFiles.Query -f $v, $push.Count, $s0, $pull.Count, $s1),
                $Message.ShouldContinue.SyncDotFiles.Caption)) {

            if (-not (Test-Path $ManifestFile)) {
                Write-Warning $Message.Warning.NoManifestFile
                
                return
            }

            $push | Invoke-DotPush Dot
            $pull | Invoke-DotPull Dot
        }
    }
}


function Invoke-DotFileSync {
    <#
    .Synopsis
      Main entry point to manage the dot file sync.      
    .Description
      This function heavily features PowerShell Choice prompts to streamline options for the user.

      Prompts the user with a basic function menu:
        Default -- Sync the files 'smartly' using the last write times.
        Push -- Just push all the local files into the archive, overriding them.
                This is similiar to backup but instead of backing files up, you are overwriting the current dots.
        Pull -- Just pull all the dots and overwrite local dots. Users should run Backup-Dots first.
        Update -- Updates the dot manifest with the current configutration.
        Exit -- Provides an easy way to cancel out without using Ctrl codes.
    
      The user can pass a -Force switch to override any subsequent confirmation prompts. 
    .Example
      Invoke-DotFileSync
    .Example 
      Invoke-DotFileSync -Force
    .Link 
      Invoke-DotCommandSync 
    #>

    param(
        # You know what you're doing and don't want to see any confirmation prompts
        [switch] $Force)

    $choices = @(
        New-ChoiceDescription $Message.Choice.InvokeDotFileSync.Sync $Message.HelpMessage.InvokeDotFileSync.Sync
        New-ChoiceDescription $Message.Choice.InvokeDotFileSync.Push $Message.HelpMessage.InvokeDotFileSync.Push
        New-ChoiceDescription $Message.Choice.InvokeDotFileSync.Pull $Message.HelpMessage.InvokeDotFileSync.Pull
        New-ChoiceDescription $Message.Choice.Common.Update $Message.HelpMessage.Common.Update
        New-ChoiceDescription $Message.Choice.Common.Exit $Message.HelpMessage.Common.Exit
    )
    $syncChoice = $Host.UI.PromptForChoice(
        $Message.PromptForChoice.InvokeDotFileSync.ChoiceCaption,
        $Message.PromptForChoice.InvokeDotFileSync.ChoiceMessage,
        $choices,
        0)

    switch ($syncChoice) {
        0 { Sync-DotFiles -Force:$Force }
        1 { Update-DotFiles -Force:$Force }
        2 { Update-LocalFiles -Force:$Force }
        3 { Update-DotManifest -Force:$Force }
        default { return }
    }
}


function Invoke-DotCommandSync {
    <#
    .Synopsis
      Main entry point to manage the dot command sync.      
    .Description
      This function heavily features PowerShell Choice prompts to streamline options for the user.

      Prompts the user with a basic function menu:
        Save -- Save command data to the dot file archive
        Invoke -- Runs all the commands in the manifest and will pull data from the archive to execute as needed.
        Update -- Updates the dot manifest with the current configutration.
        Exit -- Provides an easy way to cancel out without using Ctrl codes.
    
      The user can pass a -Force switch to override any subsequent confirmation prompts. 
    .Example
      Invoke-DotCommandSync
    .Example 
      Invoke-DotCommandSync -Force
    .Link 
      Invoke-DotFileSync 
    #>

    param(
        # You know what you're doing and don't want to see any confirmation prompts
        [switch] $Force)

    $saveParams = @{
        s  = $Message.Choice.InvokeDotCommandSync.Save
        s1 = $Message.HelpMessage.InvokeDotCommandSync.Save
    }
    $invokeParams = @{
        s  = $Message.Choice.InvokeDotCommandSync.Invoke
        s1 = $Message.HelpMessage.InvokeDotCommandSync.Invoke
    }
    $choices = @(
        New-ChoiceDescription @saveParams
        New-ChoiceDescription @invokeParams
        New-ChoiceDescription $Message.Choice.Common.Update $Message.HelpMessage.Common.Update
        New-ChoiceDescription $Message.Choice.Common.Exit $Message.HelpMessage.Common.Exit
    )
    $commandChoice = $Host.UI.PromptForChoice(
        $Message.PromptForChoice.InvokeDotCommandSync.ChoiceCaption,
        $Message.PromptForChoice.InvokeDotCommandSync.ChoiceMessage,
        $choices,
        0)

    switch ($commandChoice) {
        0 { Save-DotCommands -Force:$Force }
        1 { Invoke-DotCommands -Force:$Force }
        2 { Update-DotManifest -Force:$Force }
        default { return }
    }
}



function Backup-Dots {
    <#
    .Synopsis
      Backup local system dot files to the module.
    .Description
      Before performing a pull operation, the user can Backup dot files.
      These files can be restored to the system with Restore-Dots.

      These safeguard functions are available to the user in case dot file changes cause significant disruption.

      This function takes no parameters.
    .Example
      Backup-Dots 
    .Link
      Restore-Dots
    #>

    Get-DotManifest |
    Get-Entry |
    Invoke-DotPush Backup
}


function Restore-Dots {
    <#
    .Synopsis
      Restore local system dot files from the module.
    .Description
      Before performing a pull operation, the user can backup dot files.
      These files can be restored to the system with Restore-Dots.

      These safeguard functions are available to the user in case dot file changes cause significant disruption. 

      This function takes no parameters.
    .Example
      Restore-Dots
    .Link
      Backup-Dots 
    #>

    Get-DotManifest |
    Get-FileEntry |
    Invoke-DotPull Backup
}