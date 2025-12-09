using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.IO
using namespace System.IO.Compression
using namespace System.IO.Compression.FileSystem
using namespace System.Management.Automation
using namespace System.Text

<#
 ______  _________________________________       _______ _______ 
(  __  \(  ___  )__   __(  ____ \__   __( \     (  ____ (  ____ \
| (  \  ) (   ) |  ) (  | (    \/  ) (  | (     | (    \/ (    \/
| |   ) | |   | |  | |  | (__      | |  | |     | (__   | (_____ 
| |   | | |   | |  | |  |  __)     | |  | |     |  __)  (_____  )
| |   ) | |   | |  | |  | (        | |  | |     | (           ) |
| (__/  ) (___) |  | |  | )     ___) (__| (____/\ (____/Y\____) |
(______/(_______)  )_(  |/      \_______(_______(_______|_______)

#>

<#
.Description
  Manage your dot files
#>
 
param (
    $DefaultDirectory = "$HOME/.dotfiles/"
)

#region Setup ----------------------------------------------------------------------------------------------------------
$ModuleRoot = Split-Path $PSScriptRoot -Leaf

data Literal {
    @{
        Empty      = ''
        Space      = ' '
        Stop       = '.'
        CommaSpace = ', '
        CheckMark  = '-'
        Current    = '>'
        Newline    = "`n"
    }
}

data Setting {
    @{
        ErrorActionPreference = 'Stop'
        ConfigFile            = 'Config.psd1'
        ConfigFileBinding     = 'Config'
        ResourceFile          = 'Resources.psd1'
        ResourceFileBinding   = 'Message'
        ManifestFile          = 'dotfiles.manifest' 
        ArchiveFile           = 'dotfiles.archive'
        BackupFile            = 'dotfiles.backup'
    }
}

$ErrorActionPreference = $Setting.ErrorActionPreference
$ConfigFile = @{
    BindingVariable = $Setting.ConfigFileBinding
    BaseDirectory   = $ModuleRoot
    FileName        = $ModuleRoot + $Literal.Stop + $Setting.ConfigFile
}
$ResourceFile = @{
    BindingVariable = $Setting.ResourceFileBinding
    BaseDirectory   = $PSScriptRoot
    FileName        = $ModuleRoot + $Literal.Stop + $Setting.ResourceFile
}

# Try to import the resource file
try {
    Import-LocalizedData @ResourceFile 
}
catch {
    # Uh-oh. The module is likely broken if this file cannot be found.
    Import-LocalizedData @ResourceFile -UICulture en-US
}

data GoodConfigProperties {
    'ManifestFilePath'
    'ArchiveFilePath'
    'BackupFilePath'
}

Set-Variable -Name DefaultConfig -Option ReadOnly -Value @{
    ManifestFilePath = Join-Path $DefaultDirectory $Setting.ManifestFile
    ArchiveFilePath  = Join-Path $DefaultDirectory $Setting.ArchiveFile
    BackupFilePath   = Join-Path $DefaultDirectory $Setting.BackupFile
}

# For coherent messages
function Get-PluralNoun ($n) { if ($n -ne 1) { $Message.NounPlural } }
function Get-PluralVerb ($n) { if ($n -ne 1) { $Message.ToBePlural } else { $Message.ToBeSingular } }
 
function Assert-Config ($x, $y) {
    $xs = [HashSet[string]] $x
    $ys = [HashSet[string]] $y

    if (-not $xs.IsSubsetOf($ys)) {
        [void] $xs.ExceptWith($ys)

        throw ($Message.TerminatingError.BadConfig -f
            ($xs -join $Literal.CommaSpace),
            (PluralVerb $xs.Count),
            (PluralNoun $xs.Count),
            (PluralNoun $ys.Count),
            (PluralVerb $ys.Count),
            ($ys -join $Literal.CommaSpace))
    }
}

try {
    Import-LocalizedData @ConfigFile

    Assert-Config ($Config.Keys) $GoodConfigProperties
}
catch [PSInvalidOperationException] {
    Write-Warning $Message.Warning.ConfigFileNotFound

    $Config = $DefaultConfig
}
catch {
    Write-Error $_.Exception.Message
}

data Formatter {
    @{
        Hex = 'x'
    }
}

#endregion 
#region Helpers --------------------------------------------------------------------------------------------------------
function Test-EmptyString ([string] $s) { return [string]::IsNullOrWhiteSpace($s) }
function Test-DotFilesManifestPath { Test-Path $Config.ManifestFilePath }
function Test-DotFilesArchivePath { Test-Path $Config.ArchiveFilePath }
function Test-DotFilesBackupPath { Test-Path $Config.BackupFilePath }

#endregion
#region Types ----------------------------------------------------------------------------------------------------------

# 'Entries' used to be 'Dots' which were two seperate classes deriving from a main abstract class (three total classes)
# The same class with two different type flags is way easier to manage and keep track of
enum EntryType {
    File
    Command
}

# An enum to make filtering entry comparisons easier
enum Target {
    Same
    Local
    Archive
}

# Handy for internal read/write functions
enum DotFileChoice {
    Archive
    Backup
}

class Entry {
    [string] $Id
    [EntryType] $Type
    [string] $Target
    [string] $Source
    [string] $Hash
    [DateTime] $RecordTime
}

# A dumb class to help compare and filter entries
class EntryCompare {
    [Entry] $Entry
    [Target] $Target
}

class Manifest {
    [List[Entry]] $Entries
}

# A do nothing class that makes it much easier to smoothly serialize/deserlize PSObjects
# From Jaykul?
class PSObjectConverter : System.Management.Automation.PSTypeConverter {

    [bool] CanConvertFrom([psobject] $psSourceValue, [type] $destinationType) {
        return $false
    }

    [object] ConvertFrom(
        [psobject] $psSourceValue,
        [type] $destinationType,
        [IFormatProvider] $formatProvider,
        [bool] $ignoreCase) {

        throw [NotImplementedException]       
    }

    # The do-nothing parts.
    [bool] CanConvertFrom([object] $sourceValue, [type] $destinationType) {
        return $false
    }

    [object] ConvertFrom(
        [object] $sourceValue,
        [type] $destinationType,
        [IFormatProvider] $formatProvider,
        [bool] $ignoreCase) {

        throw [NotImplementedException]
    }

    [bool] CanConvertTo([object] $sourceValue, [type] $destinationType) {
        throw [NotImplementedException]
    }

    [object] ConvertTo(
        [object] $sourceValue,
        [type] $destinationType,
        [IFormatProvider] $formatProvider,
        [bool] $ignoreCase) {

        throw [NotImplementedException]
    }
}

# The converter that uses the above class to make xml imports/exports better
class EntryConverter : PSObjectConverter {

    [bool] CanConvertFrom([psobject] $psSourceValue, [type] $destinationType) {
        return $psSourceValue.PSTypeNames.Contains('Deserialized.Entry')
    }

    [object] ConvertFrom(
        [psobject] $psSourceValue, 
        [type] $destinationType, 
        [IFormatProvider] $formatProvider, 
        [bool] $ignoreCase) {

        $obj = [Entry] @{
            Id         = $psSourceValue.Id
            Type       = $psSourceValue.Type
            Source     = $psSourceValue.Source
            Target     = $psSourceValue.Target
            Hash       = $psSourceValue.Hash
            RecordTime = $psSourceValue.RecordTime
        }

        return $obj
    }
}

# Must register the converters with the PowerShell process
Update-TypeData -TypeName Deserialized.Entry -TargetTypeForDeserialization Entry -Force
Update-TypeData -TypeName Entry -TypeConverter EntryConverter -Force

#endregion
#region Gatekeeping ----------------------------------------------------------------------------------------------------
function Assert-Path {
    <#
    .Description
      Throw on Test-Path failure. #>

    if (-not (Test-Path $input)) {
        throw ($Message.TerminatingError.BadPath -f $_)
    }

    $true
}

#endregion
#region ClassHelpers --------------------------------------------------------------------------------------------------
function New-Entry {
    <#
    .Description
      Easily make an entry object.

      object -> EntryType -> Entry #>

    param (
        # Either a string or a hashtable with 'Pull' and 'Push' Keys.
        $Source
        ,
        # The Type of Entry.
        [EntryType] $Type
    )


    switch ($Type) {

        File {
            # Abort-- the path does not exist and there is nothing to push
            if (-not (Test-Path $Source)) {
                return
            }
            
            $value = Convert-Path $Source
            $id = $value.GetHashCode().ToString($Formatter.Hex)
            $hash = (Get-FileHash $value).Hash
            $target = $value
            $time = (Get-Item $value).LastAccessTimeUtc
        }

        Command {
            # Test for a pull command
            if (Test-EmptyString ($Source.Pull)) {
                return
            }

            # We can have a naked push command
            $value = if (Test-EmptyString $Source.Push) { $Literal.Empty } else { $Source.Push.ToString() }
            $id = $Source.Pull.GetHashCode().ToString($Formatter.Hex)
            $target = $Source.Pull.ToString()
            $hash = if (Test-EmptyString $Source.Push) { $value.GetHashCode().ToString($Formatter.Hex) } else { (Invoke-Expression $value).GetHashCode().ToString($Formatter.Hex) } 
            $time = (Get-Date -AsUTC)
        }
    }

    [Entry] @{
        Id         = $id
        Type       = $Type
        Target     = $Target
        Source     = $value
        Hash       = $hash
        RecordTime = $time
    }
}

# Entry filter functions
function Get-FileEntry { $input.Where{ $_.Type -eq [EntryType]::File } }
function Get-CommandEntry { $input.Where{ $_.Type -eq [EntryType]::Command } }

function Initialize-EntryCompare ($Entry) {
    [EntryCompare] @{
        Entry  = $Entry
        Target = [Target]::Local
    }
}

filter Set-SyncTarget {
    $entryCompare = $_
    $entry = $entryCompare.Entry


    switch ($entry.Type) {
        File {
            $target = ($entry.Target) -as [FileInfo]
            if (-not $target.Exists) {
                $entryCompare.Target = [Target]::Archive
                return $entryCompare
            }

            $targetHash = (Get-FileHash $target.FullName).Hash
            $isTargetNewer = $target.LastWriteTimeUtc -gt $entry.RecordTime
        }

        Command {
            # Need to check if the Source Command Hash is the same now

            if (Test-EmptyString $entry.Source) {
                # This command is only meant to be run on a pull so just assign Archive and continue
                $entryCompare.Target = [Target]::Archive
                return $entryCompare
            }

            $targetHash = (Invoke-Expression $entry.Source).GetHashCode.ToString($Formatter.Hex)
            $isTargetNewer = $true
        }
    }

    $entryCompare.Target =
        if ($entry.Hash -eq $targetHash) {
            [Target]::Same
        }
        elseif ($isTargetNewer) {
            [Target]::Local
        }
        else {
            [Target]::Archive
        }

    $entryCompare
}

filter New-EntryCompare  { Initialize-EntryCompare $_ | Set-SyncTarget  }

# EntryCompare filter functions
function Get-ArchiveEntryCompare { $input.Where{ $_.Target -eq [Target]::Archive } }
function Get-LocalEntryCompare { $input.Where{ $_.Target -eq [Target]::Local } }

#endregion
#region Inside ---------------------------------------------------------------------------------------------------------
function New-Manifest {
    [Manifest] @{
        Entries = @()
    }
}

filter Add-FileEntry ($Source) { $_.Entries.Add((New-Entry $Source File)); $_ }
filter Add-CommandEntry ([scriptblock] $PullCommand, [scriptblock] $PushCommand) {

    $Hash = @{
        Pull = $PullCommand
        Push = $PushCommand
    }

    $_.Entries.Add((New-Entry @Hash Command))

    $_
}

filter Complete-Manifest { $_ | ForEach-Object Entries } 

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


function New-DotFile ([DotFileChoice] $To) {
   $Path =
    switch ($To) {
        Archive { $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Config.ArchiveFilePath) }
        Backup { $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Config.BackupFilePath) }
    }

    $zipArchive = [ZipFile]::Open($path, [ZipArchiveMode]::Create)
    $zipArchive.Dispose()

    Get-Item $Path
}



filter Invoke-DotPush ([DotFileChoice] $To) {
    $path =
        switch ($To) {
            Archive { Convert-Path $Config.ArchiveFilePath }
            Backup { Convert-Path $Config.BackupFilePath }
        }
    $entry = $_

    if (Test-EmptyString ($entry.Source)) {
        return
    }

    $zipArchive = [ZipFile]::Open($Path, [ZipArchiveMode]::Update, [Encoding]::UTF8)
    $zipEntry = $zipArchive.CreateEntry($entry.Id)

    switch ($entry.Type) {
        File {
            $file = [File]::OpenRead($entry.Target)
            $file.CopyTo($zipEntry.Open())
            $file.Dispose()
        }

        Command {
            $writer = [StreamWriter]::new($zipEntry.Open())
            $content = (Invoke-Expression $entry.Source).ToString()
            $writer.Write($content)
            $writer.Dispose()
        }
    }

    $zipArchive.Dispose()
}


filter Invoke-DotPull ([DotFileChoice] $From) {
    $path =
    switch ($From) {
        Archive { Convert-Path $Config.ArchiveFilePath }
        Backup { Convert-Path $Config.BackupFilePath }
    }
    $entry = $_
    $f = New-ScriptBlock $entry.Target

    if (Test-EmptyString $entry.Source) {
        return $f.Invoke()
    }

    $zipArchive = [ZipFile]::OpenRead($path)
    $zipEntry = $zipArchive.GetEntry($entry.Id)

    switch ($entry.Type) {
        File {
            [ZipFileExtensions]::ExtractToFile($zipEntry, $entry.Target, $true)
        }

        Command {
            $entryStream = $zipEntry.Open()
            $memoryStream = [MemoryStream]::new()

            $entryStream.CopyTo($memoryStream)

            $z = $memoryStream.ToArray()

            # $z.ForEach($f)
            $z.ForEach{ Write-Host "Executing '$z' in '$f'" }

            $memoryStream.Dispose()
            $entryStream.Dispose()
        }
    }

    $zipArchive.Dispose()
}

function Update-LocalFiles {
    [CmdletBinding()]
    param([switch] $Force)

    if (-not (Test-Path $Config.ManifestFilePath)) {
        Write-Warning $Message.Warning.NoManifestFile

        return
    }

    Write-Verbose 'Backing up Files'
    Backup-DotFiles

    $fileEntries = Import-DotFilesManifest | Get-FileEntry 
    if ($Force -or $PSCmdlet.ShouldContinue(
            ($Message.ShouldContinue.UpdateLocalFiles.Query -f $fileEntries.Count),
            $Message.ShouldContinue.UpdateLocalFiles.Caption)) {
        $fileEntries =  Invoke-DotPull Archive
    }
}


function Update-DotFiles {
    [CmdletBinding()]
    param([switch] $Force)

    if (-not (Test-Path $Config.ManifestFilePath)) {
        Write-Warning $Message.Warning.NoManifestFile

        return
    }

    $fileEntries = Import-DotFilesManifest | Get-FileEntry 
    
    if ($Force -or $PSCmdlet.ShouldContinue(
            ($Message.ShouldContinue.UpdateDotFiles.Query -f $fileEntries.Count),
            $Message.ShouldContinue.UpdateDotFiles.Caption)) {
        $fileEntries |  Invoke-DotPush Archive
    }
}

function Invoke-DotCommands {
    [CmdletBinding()]
    param([switch] $Force)

    if (-not (Test-Path $Config.ManifestFilePath)) {
        Write-Warning $Message.Warning.NoManifestFile

        return
    }

    $cmdEntries = Import-DotFilesManifest | Get-CommandEntry

    if ($Force -or $PSCmdlet.ShouldContinue(
            ($Message.ShouldContinue.InvokeDotCommands.Query -f $cmdEntries.Count),
            $Message.ShouldContinue.InvokeDotCommands.Caption)) { 

        $cmdEntries |  Invoke-DotPull Archive
    }
}


function Save-DotCommands {
    [CmdletBinding()]
    param([switch] $Force)
    
    if (-not (Test-Path $Config.ManifestFilePath)) {
        Write-Warning $Message.Warning.NoManifestFile

        return
    }

    $cmdEntries = Import-DotFilesManifest | Get-CommandEntry
    
    if ($Force -or $PSCmdlet.ShouldContinue(
            ($Message.ShouldContinue.SaveDotCommands.Query -f $cmdEntries.Count),
            $Message.ShouldContinue.SaveDotCommands.Caption)) {

        $cmdEntries | Invoke-DotPush Archive
    }
}

filter Get-NewerEntry {
    $_ | New-EntryCompare 
}


function Get-PushForSync {
    Import-DotFilesManifest |
        Get-NewerEntry |
        Get-LocalEntryCompare |
        ForEach-Object Entry
}


function Get-PullForSync {
    Import-DotFilesManifest |
        Get-NewerEntry |
        Get-ArchiveEntryCompare | 
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
    }

    end {
        if (-not (Test-Path $Config.ManifestFilePath)) {
            throw 'shit'
        }

        if ($Force -or $PSCmdlet.ShouldContinue(
                ($Message.ShouldContinue.SyncDotFiles.Query -f
                (PluralVerb $push.Count),
                $push.Count,
                (PluralNoun $push.Count),
                $pull.Count,
                (PluralNoun $pull.Count)),
                $Message.ShouldContinue.SyncDotFiles.Caption)) {

            if (-not (Test-Path $Config.ManifestFilePath)) {
                Write-Warning $Message.Warning.NoManifestFile
                
                return
            }

            $push | Invoke-DotPush Archive
            $pull | Invoke-DotPull Archive
        }
    }
}


#endregion
#region Outside --------------------------------------------------------------------------------------------------------
function Initialize-DotFilesManifest {
    [CmdletBinding(SupportsShouldProcess)]

    param()

    if (Test-DotFilesManifestPath) {
        return
    }

    if ($PSCmdlet.ShouldProcess((DotFilesManifestPath), 'Create')) {
        New-Item -Type File -Path $Config.ManifestFilePath -Force
    }
}

function Initialize-DotFilesArchive {
    [CmdletBinding(SupportsShouldProcess)]

    param()

    if (Test-DotFilesArchivePath) {
        return
    }

    if ($PSCmdlet.ShouldProcess((DotFilesArchivePath), 'Create')) {
        New-DotFile Archive
    }
}


function Initialize-DotFilesBackup {
    [CmdletBinding(SupportsShouldProcess)]

    param()

    if (Test-DotFilesBackupPath) {
        return
    }

    if ($PSCmdlet.ShouldProcess((DotFilesBackupPath), 'Create')) {
        New-DotFile Backup
    }
}

function Initialize-DotFiles {
    [CmdletBinding(SupportsShouldProcess)]

    param ()

    Initialize-DotFilesManifest
    Initialize-DotFilesArchive
    Initialize-DotFilesBackup
}

function Get-DotFilesManifestPath {
    [CmdletBinding()]
    #.Description
    #  Gets the DotFiles Manifest Path
    param()

    $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Config.ManifestFilePath)
}
function Get-DotFilesArchivePath {
    [CmdletAttribute()]
    #.Description
    #  Gets the DotFiles Archive Path
    param ()

    $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Config.ArchiveFilePath)
}
function Get-DotFilesBackupPath {
    [CmdletAttribute()]
    #.Description
    #  Gets the DotFiles Backup Path
    param()

    $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Config.BackupFilePath)
}

function Set-DotFilesManifestPath {
    <#
    .Synopsis
      Sets the dot files manifest path
    .Description
      Sets the dot files manifest path if path exists
    .Example
      Set-DotFileManifestPath $myPath
    #>
    [CmdletBinding()]

    param (
        [Parameter(Mandatory)]
        [ValidateScript({Assert-Path})]
        $Path # The path to set
    )

    $Config.ManifestFilePath = $Path
}


function Set-DotFilesArchivePath {
    <#
    .Synopsis
      Sets the dot files manifest path
    .Description
      Sets the dot files manifest path if path exists
    .Example
      Set-DotFileArchivePath $myPath
    #>
    [CmdletAttribute()]

    param (
        [Parameter(Mandatory)]
        [ValidateScript({Assert-Path})]
        $Path # The path to set
    )

    $Config.ArchiveFilePath = $Path
}


function Set-DotFilesBackupPath {
    <#
    .Synopsis
      Sets the dot files manifest path
    .Description
      Sets the dot files manifest path if path exists
    .Example
      Set-DotFileBackupPath $myPath
    #>
    [CmdletAttribute()]

    param (
        [Parameter(Mandatory)]
        [ValidateScript({Assert-Path})]
        $Path # The path to set
    )

    $Config.BackupFilePath = $Path
}

function New-DotFilesEntry {
    <#
    .Description
      A wrapper for New-Entry
    #>
    [CmdletBinding(DefaultParameterSetName = 'File')]

    param (
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'File')]
        [string] $Source
        ,
        [Parameter(Mandatory, ParameterSetName = 'Command')]
        [scriptblock]$Pull
        ,
        [Parameter(ParameterSetName = 'Command')]
        [scriptblock] $Push
    )

    process {

        switch ($PSCmdlet.ParameterSetName) {
            File {
                New-Entry -Source $Source -Type File
                
            }

            Command {
                $Hash = @{
                    Push = $Push
                    Pull = $Pull
                }
                New-Entry -Source $Hash -Type Command                
            }
        }
    }
}


function Import-DotFilesManifest {

    begin {
        $f = { [PSSerializer]::Deserialize($_) }
    }
     
    process {
        (Get-Content -Raw -Encoding UTF8 -Path (DotFilesManifestPath)).ForEach($f)
    }
}

function Export-DotFilesManifest {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]

    param(
        [Parameter(
            ValueFromPipeline,
            ValueFromPipelineByPropertyName)]
        [List[Entry]] $InputObject
    )
    
    begin {
        $a = [List[Entry]] @()
        $f = { [void] $a.Add($_) }

        if (-not(Test-DotFilesManifestPath)) {
            Initialize-DotFilesManifest
        }
    }

    process {
        $InputObject.ForEach($f)
    }

    end {
        if ($PSCmdlet.ShouldProcess((DotFilesManifestPath), $Message.ShouldProcess.ExportDotFile)) {
            [PSSerializer]::Serialize($a.ToArray()) | Out-File (DotFilesManifestPath) -Encoding utf8 -Verbose
        }
    }
}


function Invoke-DotFilesSync {
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
        New-ChoiceDescription $Message.Choice.Common.Exit
    )
    $commandChoice = $Host.UI.PromptForChoice(
        $Message.PromptForChoice.InvokeDotCommandSync.ChoiceCaption,
        $Message.PromptForChoice.InvokeDotCommandSync.ChoiceMessage,
        $choices,
        0)

    switch ($commandChoice) {
        0 { Save-DotCommands -Force:$Force }
        1 { Invoke-DotCommands -Force:$Force }
        default { return }
    }
}



function Backup-DotFiles {
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

    Import-DotFilesManifest |
        Get-FileEntry |
        Invoke-DotPush Backup
}


function Restore-DotFiles {
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

    Import-DotFilesManifest |
        Get-FileEntry | 
        Invoke-DotPull Backup
}
#endregion

