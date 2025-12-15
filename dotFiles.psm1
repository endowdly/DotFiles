using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.IO
using namespace System.IO.Compression
using namespace System.IO.Compression.FileSystem
using namespace System.Management.Automation
using namespace System.Text
using namespace System.Security.Cryptography

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
    BaseDirectory   = $PSScriptRoot
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
    $xs = [HashSet[string]] [string[]]$x
    $ys = [HashSet[string]] $y

    if (-not $xs.IsSubsetOf($ys)) {
        [void] $xs.ExceptWith($ys)

        # BadConfig      = '''{0}'' {1} not a valid config key{2}. Valid key{3} {4}: {5}'
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
        DoubleHex = 'x2'
    }
}

#endregion 
#region Helpers --------------------------------------------------------------------------------------------------------
function Test-EmptyString ($s) { return [string]::IsNullOrWhiteSpace($s) }
function ConvertTo-FileInfoObject ($s) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($s) -as [FileInfo] }
function Test-DotFilesManifestPath { (ConvertTo-FileInfoObject $Config.ManifestFilePath).Exists }
function Test-DotFilesArchivePath { (ConvertTo-FileInfoObject $Config.ArchiveFilePath).Exists }
function Test-DotFilesBackupPath { (ConvertTo-FileInfoObject $Config.BackupFilePath).Exists }
function Remove-StringWhiteSpace ($s) { $p = { -not ([char]::IsWhiteSpace($_)) }; -join ($s.ToCharArray().Where($p)) }
function Get-HashString ([string] $s) { -join ([SHA256]::Create().ComputeHash([Encoding]::UTF8.GetBytes($s)).ForEach{ $_.ToString($Formatter.DoubleHex) }) }
function New-ScriptBlock ($s) { [scriptblock]::Create($s) }
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
    [string]    $Id
    [EntryType] $Type
    [string]    $Target
    [string]    $Source
    [string]    $Hash
    [DateTime]  $RecordTime
    [string]    $FriendId
}

# A dumb class to help compare and filter entries
class EntryCompare {
    [Entry] $Entry
    [Target] $Target
}

class Manifest {
    [List[Entry]] $EntryList
    [HashSet[string]] $FriendIdSet

    [bool] IsEmpty() {
        return ($this.EntryList.Count -eq 0 -and $this.FriendIdSet.Count -eq 0)
    }
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
#region ClassHelpers --------------------------------------------------------------------------------------------------
function New-Entry {
    <#
    .Description
      Make an entry object.

      object -> EntryType -> Entry #>

    [CmdletBinding(DefaultParameterSetName = 'File')]

    param (
        [Parameter(ParameterSetName = 'File')]
        [string] $Source
        ,
        [Parameter(ParameterSetName = 'Command')]
        [string] $Push  
        ,
        [Parameter(ParameterSetName = 'Command')]
        [string] $Pull
        ,
        [string] $FriendId
        ,
        [Parameter(ParameterSetName = 'Command')]
        [switch] $Command
    )

    switch ($PSCmdlet.ParameterSetName) {

        File {

            $x = ConvertTo-FileInfoObject $Source

            if (-not $x.Exists) {
                Write-Verbose "${x.Name} Does Not Exist"
                return
            }

            if (-not $PSBoundParameters.ContainsKey('FriendId')) {
                $FriendId = $x.Name
            }

            $value = $target = $x.FullName                      # ! Double assign
            $id = $value.GetHashCode().ToString($Formatter.Hex) # This id will always point to the same path
            $hash = (Get-FileHash $value).Hash                  # This is the default file hash sha-256
            $time = (Get-Item $value).LastAccessTimeUtc         # Hashing fallback
        }

        Command {

            # We can have a naked push command
            $value = if (Test-EmptyString $Push) { $Literal.Empty } else { $Push } # No nulls please
            $id = $Pull.GetHashCode().ToString($Formatter.Hex)
            $target = $Pull
            $hashStr = (New-ScriptBlock $value).Invoke()
            $hash = HashString $hashStr
            $time = Get-Date -AsUTC
        }

        Default { Write-Error $Message.TerminatingError.What }
    }

    [Entry] @{
        Id         = $id
        Type       = $PSCmdlet.ParameterSetName
        Target     = $Target
        Source     = $value
        Hash       = $hash
        RecordTime = $time
        FriendId   = (Remove-StringWhiteSpace $FriendId)
    }
}

filter Update-Entry {
    $entry = $_

    switch ($entry.Type) {

        File {
            New-Entry -FriendId $entry.FriendId -Source $entry.Source 
        }

        Command {
            New-Entry -FriendId $entry.FriendId -Push $entry.Push -Pull $entry.Pull
        }
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

            $targetHashStr = [scriptblock]::Create($entry.Source).Invoke()
            $targetHash = HashString $targetHashStr
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

filter Get-EntryCompare  { Initialize-EntryCompare $_ | Set-SyncTarget  }

# EntryCompare filter functions
function Get-ArchiveEntryCompare { $input.Where{ $_.Target -eq [Target]::Archive } }
function Get-LocalEntryCompare { $input.Where{ $_.Target -eq [Target]::Local } }

function New-Manifest {
    <#
    .Description
      Creates a new manifest object #>

    [Manifest] @{
        EntryList = @()
        FriendIdSet = @()
    }
}

filter Add-Entry ($x) {
    <#
    .Description
      Adds a piped Entry to a Manifest object if the Entry does not have a duplicate Token property.
      If the Token property of the Entrty object already exists in the Manifest, the Entry is ignored.
      A successful operation modifies the Manifest object.
      A failed operation emits an error.
      seq<Entry> -> Manifest -> () #> 

    if ($null -eq $_) {
        return
    }

    if ($x.FriendIdSet.Add($_.FriendId)) {
        [void] $x.EntryList.Add($_)
    }
    else {
        Write-Error ($Message.Error.AddEntry -f $_.FriendId)
    }
}

filter ConvertFrom-Manifest {
    <#
    .Description
      Strips an EntryList off a Manifest Object #>
    
    $_.EntryList.ToArray()
}

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
#region Inside ---------------------------------------------------------------------------------------------------------
function Import-DotFilesManifest {
    <#
    .Description
    .Notes
        () -> [Entry[]]
    #>

    begin {
        $f = { [PSSerializer]::Deserialize($_) }
    }
     
    process {

        if (-not (Test-DotFilesManifestPath)) {
            Write-Warning ($Message.Warning.NoManifestFile -f (DotFilesManifestPath))

            return 
        }

        (Get-Content -Raw -Encoding utf8 -Path (DotFilesManifestPath)).ForEach($f)
    }
}

filter ConvertTo-Manifest { $_ | Add-Entry (New-Manifest) }

function Initialize-ZipFile ($Path) {
    $zipArchive = [ZipFile]::Open($Path, [ZipArchiveMode]::Create)
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

    Update-DotFilesManifest
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

    Update-DotFilesManifest
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
        $fileEntries | Invoke-DotPull Archive
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

        $cmdEntries | Invoke-DotPull Archive

        Update-DotFilesManifest
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

        Update-DotFilesManifest 
    }
}



function Get-PushForSync {
    $DotFiles.CurrentManifest |
        ConvertFrom-Manifest |
        Get-EntryCompare |
        Get-LocalEntryCompare |
        ForEach-Object Entry
}


function Get-PullForSync {
    $DotFiles.CurrentManifest | 
        ConvertFrom-Manifest |
        Get-EntryCompare |
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
            Write-Warning $Message.Warning.NoManifestFile

            return
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

# Module Variables go here
$DotFiles = @{
    LastManifest = New-Manifest
    CurrentManifest = New-Manifest
    ManifestFilePath = $Config.ManifestFilePath
    ArchiveFilePath = $Config.ArchiveFilePath
    BackupFilePath = $Config.BackupFilePath
}

#endregion
#region Outside --------------------------------------------------------------------------------------------------------
function Initialize-DotFilesManifest {
    [CmdletBinding(SupportsShouldProcess)]

    param()

    if (Test-DotFilesManifestPath) {
        return
    }

    if (-not (Test-Path -IsValid (DotFilesManifestPath))) {
        Write-Error ($Message.TerminatingError.RealBadPath -f (DotFilesManifestPath))
    }

    if ($PSCmdlet.ShouldProcess((DotFilesManifestPath), 'Create')) {
        New-Item -Type File -Path (DotFilesManifestPath) -Force
    }
}

function Initialize-DotFilesArchive {
    [CmdletBinding(SupportsShouldProcess)]

    param()

    if (Test-DotFilesArchivePath) {
        return
    }

    if (-not (Test-Path -IsValid (DotFilesArchivePath))) {
        Write-Error ($Message.TerminatingError.RealBadPath -f (DotFilesArchivePath))
    }

    if ($PSCmdlet.ShouldProcess((DotFilesArchivePath), 'Create')) {
        Initialize-ZipFile (DotFilesArchivePath)
    }
}


function Initialize-DotFilesBackup {
    [CmdletBinding(SupportsShouldProcess)]

    param()

    if (Test-DotFilesBackupPath) {
        return
    }

    if (-not (Test-Path -IsValid (DotFilesBackupPath))) {
        Write-Error ($Message.TerminatingError.RealBadPath -f (DotFilesBackupPath))
    }

    if ($PSCmdlet.ShouldProcess((DotFilesBackupPath), 'Create')) {
        Initialize-ZipFile (DotFilesBackupPath)
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
    param ()

    $PSCmdlet.GetUnresolvedProviderPathFromPSPath($DotFiles.ManifestFilePath)
}
function Get-DotFilesArchivePath {
    [CmdletBinding()]
    #.Description
    #  Gets the DotFiles Archive Path
    param ()

    $PSCmdlet.GetUnresolvedProviderPathFromPSPath($DotFiles.ArchiveFilePath)
}
function Get-DotFilesBackupPath {
    [CmdletBinding()]
    #.Description
    #  Gets the DotFiles Backup Path
    param ()

    $PSCmdlet.GetUnresolvedProviderPathFromPSPath($DotFiles.BackupFilePath)
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

    $DotFiles.ManifestFilePath = $Path
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

    $DotFiles.ArchiveFilePath = $Path
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

    $DotFiles.BackupFilePath = $Path
}

function New-DotFilesManifestEntry {
    <#
    .Description
      A wrapper for New-Entry
    #>
    [CmdletBinding(DefaultParameterSetName = 'File')]

    param (
        [Parameter(
            ValueFromPipeline,
            Mandatory,
            Position = 1,
            ParameterSetName = 'File')]
        [string] $Source
        ,
        [Parameter(
            ValueFromPipelineByPropertyName,
            ParameterSetName = 'Command',
            Position = 3)]
        [string] $Push
        ,
        [Parameter(
            ValueFromPipelineByPropertyName,
            ParameterSetName = 'Command',
            Mandatory,
            Position = 2)]
        [string] $Pull
        ,
        [Parameter(
            ValueFromPipelineByPropertyName,
            ParameterSetName = 'File',
            Position = 0)]
        [Parameter(
            ValueFromPipelineByPropertyName,
            ParameterSetName = 'Command',
            Mandatory,
            Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string] $FriendId
        ,
        [Parameter(Position = 0, ParameterSetName = 'Command')]
        [switch] $Command
    )

    process {
        New-Entry @PSBoundParameters
    }
}

function Export-DotFilesManifest {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [Alias('Save-DotFilesManifest')]

    param()
    
    if ($PSCmdlet.ShouldProcess((DotFilesManifestPath), $Message.ShouldProcess.ExportDotFile)) {
        [PSSerializer]::Serialize($DotFiles.CurrentManifest.EntryList) | Out-File (DotFilesManifestPath) -Encoding utf8 

        Update-DotFilesManifest -FromFile
    }
}

function Update-DotFilesManifest {
    <#
    .Synopsis
      Update the manifest in memory with the contents of the manifest file.
    #>

    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'Low')]

    param ([Switch] $FromFile)

    if ($PSCmdlet.ShouldProcess($Path, $Message.ShouldProcess.UpdateManifest)) {

        $DotFiles.LastManifest = $DotFiles.CurrentManifest

        if ($FromFile.IsPresent) {

            $FileManifest = Import-DotFilesManifest 

            if ($null -eq $FileManifest) {
                return
            }
            
            $DotFiles.CurrentManifest = Import-DotFilesManifest | ConvertTo-Manifest
        }

        $DotFiles.CurrentManifest =
            $DotFiles.CurrentManifest |
            ConvertFrom-Manifest |
            Update-Entry |
            ConvertTo-Manifest
    }
}

function Get-DotFilesManifestEntry {
    <#
    .Synopsis
      Returns Entry objects filtered by FriendlyId strings.
    .Notes
      string[] -> string[] -> bool -> Entry[] maybe
    #>

    [CmdletBinding()]
    [OutputType([Entry[]])]

    param (
        [Parameter(
            Position = 0,
            ValueFromRemainingArguments)]
        [ArgumentCompleter({
            param ($cmdName, $paramName, $wordToComplete)

            (Get-DotFilesManifestEntry).FriendId.Where{ $_ -like "${wordToComplete}*" } })]
        [string[]] $FriendId = '*'
        ,
        [Alias(
            'PathOnly',
            'ValueOnly')]
        [switch] $TargetPathOnly
    )

    begin {
        $f = {
            $currentId = $_
            $p = { $_.FriendId -like $currentId }

            $x.Where($p)
        }
        $x = [List[Entry]] @()
        $y = [List[Entry]] @()
        $g = { $y.Add($_) }

        filter Add-ToList { $x.Add($_) }
    }

    process {
        $DotFiles.CurrentManifest |
            ConvertFrom-Manifest |
            Add-ToList

        [void] $FriendId.ForEach($f).ForEach($g)
    }

    end {
        if ($TargetPathOnly.IsPresent) {
            $y.ToArray().Target
        }
        else {
            $y.ToArray()
        }
        
    }
}

function Add-DotFilesManifestEntry {
    <#
    .Synopsis
      Adds an Entry object to the Manifest.
    .Description
      Adds an Entry object to the Manifest.

      Think of an Entry object like a bookmark.
      Each has a FriendId property and a JumpPath property. 
      The FriendId is the users chosen short name or bookmark name for each JumpPath.
      The JumpPath property is a directory in the file-system they likely visit often.

      The Manifest is an internal memory collection that validates and stores Entry objects.
      It does not allow Entry objects with duplicate FriendIds.
      However, it will allow many Entry objects that point to the same JumpPath. 
      
      JumpPath can point to paths that do not yet exist.

      Returns the Entry object added unless the Silent switch parameter is used.
    .Example
      Add-ManifestEntry -FriendId docs -Path ~/Documents

      Adds an Entry with the FriendId property 'docs' pointing to the user's Documents directory.
    .Example
      Add-ManifestEntry -FriendId here

      Adds an Entry with the FriendId property 'here' pointing to the current working directory. 
    .Example
      Add-ManifestEntry -FriendId there -Path $there -Silent

      Adds an Entry with the FriendId property 'there' pointing to the path at there.
      Does return the Entry object created and added.
    .Link
      Get-ManifestEntry
    .Link
      Remove-ManifestEntry
    .Link
      Export-ManifestEntry
    .Outputs
      Entry

      Returns the Entry object added unless the Silent switch parameter is used.
    .Notes
      string -> string -> bool? -> Entry?
    #>

    [CmdletBinding(
        DefaultParameterSetName = 'Entry',
        SupportsShouldProcess,
        ConfirmImpact = 'Low')]

    param(
        [Parameter(
            ParameterSetName = 'Entry',
            ValueFromPipeline,
            ValueFromPipelineByPropertyName)]
        [Alias('EntryToAdd')]
        $Entry
        ,
        # Do not emit the Entry object.
        [switch] $Silent
        ,
        [Parameter(ParameterSetName = 'File')]
        [string] $Source
        ,
        [Parameter(ParameterSetName = 'Command')]
        [string] $Push
        ,
        [Parameter(ParameterSetName = 'Command')]
        [string] $Pull
        ,
        [Parameter(ParameterSetName = 'File')]
        [Parameter(ParameterSetName = 'Command')]
        [string] $FriendId
    )

    process {

        switch ($PSCmdlet.ParameterSetName) {

            File {
                $Entry = New-DotFilesManifestEntry -FriendId $FriendId -Source $Source
            }

            Command {
                $Entry = New-DotFilesManifestEntry -FriendId $FriendId -Pull $Pull -Push $Push
            }

        }
   
        $Msg = $Message.ShouldProcess.AddManifestEntry -f $Entry.FriendId 

        if ($PSCmdlet.ShouldProcess($Entry.Target, $Msg)) {
            $Entry | Add-Entry ($DotFiles.CurrentManifest)
        }
    }

    end { 
        if ($Silent.IsPresent) {
            return
        }

        $Entry
    }
}

# Done: Tab-Completion on tokens with partial matching @endowdly 
function Remove-DotFilesManifestEntry {
    <#
    .Synopsis
      Removes an Entry from the navigation database.
    .Description
      Removes an Entry from the navigation database.

      The function accepts FriendId arguments on the pipeline, from the parameter, and from remaining arguments.
      If a FriendId property does not exist on any Entry objects, does nothing and continues.

      Unlike Get-ManifestEntry, Remove- does not accept wildcard FriendIds.
      This is intentional in order to ensure that incorrect FriendIds are not removed by accident.
      Remove- does accept FriendIds returned from Get-ManifestEntry.

      Returns the remaining Entry array in the database if the Silent parameter switch is not used. 
    .Example
      Remove-ManifestEntry -FriendId 'this', 'that'

      Removes Entry objects with FriendIds this and that, if they exist.
    .Example
      Remove-ManifestEntry this that

      Removes Entry objects with FriendIds this and that, if they exist.
    .Example
      Get-ManifestEntry this that | Remove-ManifestEntry 

      Removes Entry objects with FriendIds this and that, if they exist.
    .Link
      Get-ManifestEntry
    .Link
      Add-ManifestEntry
    .Link
      Export-ManifestEntry 
    .Notes
      string[] -> bool -> Database?
    #>

    [CmdletBinding()]
    [OutputType([Entry[]])]

    param(
        # The FriendIds to remove from the Database.
        [Parameter(
            ValueFromPipeline,
            ValueFromRemainingArguments,
            ValueFromPipelineByPropertyName)]
        [ArgumentCompleter({ 
            param ($cmdName, $paramName, $wordToComplete)

            (Get-DotFilesManifestEntry).FriendId.Where{ $_ -like "${wordToComplete}*" } })]
        [string[]] $FriendId
        , 
        # Do not return a Database object.
        [switch] $Silent
    ) 

    begin {
        $f = {
            $x = Get-ManifestEntry $_

            if ($null -ne $x) { 
                [void] $DotFiles.CurrentManifest.EntryList.Remove($x)
                [void] $DotFiles.CurrentManifest.FriendIdSet.Remove($_)
            }
        }
    }

    process {
        $FriendId.ForEach($f)
    }

    end {
        if ($Silent.IsPresent) { 
            return
        }

        $DotFiles.CurrentManifest.EntryList.ToArray()
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
                This is similiarDotFilesManifest but instead of backing files up, you are overwriting the current dots.
        Pull -- JustDotFilesManifest the dots and overwrite local dots. Users should run Backup-Dots first.
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

    $DotFiles.CurrentManifest | 
        ConvertFrom-Manifest |
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

    $DotFiles.CurrentManifest | 
        ConvertFrom-Manifest |
        Get-FileEntry | 
        Invoke-DotPull Backup
}
#endregion

Update-DotFilesManifest -FromFile 
