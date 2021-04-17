using namespace System.IO
using namespace System.Collections.Generic
using namespace System.Management.Automation

param(
    [Parameter(
        Mandatory,
        HelpMessage = 'Enter a mode, Update or Backup')]
    [ValidateSet('Update', 'Backup')]
    [string] $Mode
    ,
    [switch] $Force
) 

data Message {
    @{
        InvalidConfig = '''{0}'' {1} not a valid config key. Valid keys are: {2}'
        TerminatingError = @{
            ConfigNotFound = 'Fatal: config file ''{0}'' not found or invalid!'
            What = 'Fatal: you somehow reached the unreachable!'
        } 
        ShouldContinue = @{
            ExpandDotFiles = 'Continue? This will likely overwrite your dot files; backup recommended.'
            CompressDotFile = 'Continue? You will overwrite the dotfile archive.'
        }
    }
}

data Setting {
    @{
        ArchivePath = 'dots.xml'
        ErrorActionPreference = 'Stop'
        VerbosePreference = 'Continue'
        BindingVariable = 'Config'
        FileName = 'dots.config.psd1'
    }
}

data Validation {
    'PathVariable'
    'Path'
    'Command' 
}

data CommandValidation {
    'Compress'
    'Expand'
}

$ErrorActionPreference = $Setting.ErrorActionPreference
$VerbosePreference = $Setting.VerbosePreference

Join-Path $PSScriptRoot $Setting.ArchivePath | Set-Variable DotsFile -Option ReadOnly

class Entry {
    [string[]] $Content
    [scriptblock] $CompressCommand 

    [void] Compress() {
        $this.Content = $this.CompressCommand.Invoke()
    } 

    [void] SetContent($s) {
        $this.Content = $s
    }
}


class DotEntry : Entry {
    [string] $Target
    [string] $ExpandedTarget

    hidden [FileInfo] $TargetObject

    DotEntry([string] $s) { 
        $this.Target = $s

        $this.ExpandTarget()

        if ($this.TargetObject.Exists) {
            $this.CompressCommand = { Get-Content -Path $this.TargetObject.FullName -Verbose }
        }
    } 

    DotEntry([string] $s, [string[]] $x) {
        $this.Content = $x 
        $this.Target = $s

        $this.ExpandTarget()

        if ($this.TargetObject.Exists) {
            $this.CompressCommand = { Get-Content -Path $this.TargetObject.FullName -Verbose }
        }
    }

    [void] Expand([bool] $b) {
        $this.ExpandTarget()

        $isValidPath = 
            try {
                [Path]::GetPathRoot($this.TargetObject.FullName)
                [Path]::GetDirectoryName($this.TargetObject.FullName)
                [Path]::GetFileName($this.TargetObject.FullName)

                $true
            }
            catch {
                $false 
            }

        if ($this.TargetObject.Exists -or ($b -and $isValidPath)) {
            $this.Content | Out-File $this.TargetObject.FullName -Encoding UTF8 -Verbose
        }
    }

    hidden [void] ExpandTarget() {
        $sb = [scriptblock]::Create($this.Target)
        $this.ExpandedTarget = $sb.Invoke()
        $this.TargetObject = $this.ExpandedTarget -as [FileInfo]
    }
}


class DotCommand : Entry {
    [scriptblock] $ExpandCommand

    [void] Expand() {
        if (!$this.Content) {
            $this.ExpandCommand.Invoke()
        }
        else { 
            $this.Content.ForEach($this.ExpandCommand)
        }
    } 

    [void] Expand([bool] $b) { 
        $this.Expand()
    }
}


function Assert-Config ($x, $y) {
    $xs = [HashSet[string]] $x
    $ys = [HashSet[string]] $y

    if (!$xs.IsSubsetOf($ys)) {
        [void] $xs.ExceptWith($ys) 

        $isAre = ('is', 'are')[$xs.Count -gt 1]

        throw ($Message.InvalidConfig -f ($xs -join ', '), $isAre, ($ys -join ', ')) 
    } 
}


$ConfigFile = @{
    BindingVariable = $Setting.BindingVariable
    BaseDirectory = $PSScriptRoot
    FileName = $Setting.FileName
}
try {
    Import-LocalizedData @ConfigFile
    Assert-Config ($Config.Keys -as [string[]]) $Validation
    Assert-Config ($Config.Command.Keys -as [string[]]) $CommandValidation
} 
catch { 
    Write-Error $_ -ErrorAction Continue 
    Write-Error ($Message.TerminatingError.ConfigNotFound -f $ConfigFile.FileName) 
}


#region Setup ------------------------------------------------------------------ 
$Config.PathVariable.GetEnumerator().ForEach{
    $p = [Scriptblock]::Create($_.Value)
    $v = $p.Invoke() -as [string]
    
    Set-Variable $_.Key $v -Option ReadOnly
}

$File = $Config.Path.ForEach{ [DotEntry] $_ }
$Command = $Config.Command.ForEach{
    [DotCommand] @{
        CompressCommand = [Scriptblock]::Create($_.Compress)
        ExpandCommand = [Scriptblock]::Create($_.Expand)
    }
} 
$Entry = [Entry[]] @($File + $Command)


function Compress-DotFiles {
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'Low')]

    param()

    $Entry.ForEach{ if ($null -ne $_.CompressCommand) { $_.Compress() } } 

    if ($PSCmdlet.ShouldContinue($Message.ShouldContinue.CompressDotFile, $DotsFile)) {
        [PSSerializer]::Serialize($Entry) | Out-File $DotsFile -Encoding utf8 -Verbose
    }
}

function Expand-DotFiles { 
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '')] # it's RIGHT there!?
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'Low')]

    param([switch] $Force)

    $raw = Get-Content -Raw -Encoding UTF8 -Path $DotsFile
    $dots = [PSSerializer]::Deserialize($raw)
    $file = $dots.
        Where{ $_.PSObject.TypeNames -contains 'Deserialized.DotEntry' }.
        ForEach{ ([DotEntry]::new($_.Target, $_.Content)) }
    $cmd = $dots.Where{ $_.PSObject.TypeNames -contains 'Deserialized.DotCommand' }.ForEach{
        [DotCommand] @{
            ExpandCommand = [scriptblock]::Create($_.ExpandCommand)
            CompressCommand = [scriptblock]::Create($_.CompressCommand)
            Content = $_.Content
        }
    }
    $dots = @($file + $cmd)
    $f = 
        if ($Force.IsPresent) {
            { $_.Expand($true) }
        }
        else {
            { $_.Expand($false) }
        }

    if ($PSCmdlet.ShouldContinue($Message.ShouldContinue.ExpandDotFiles, $DotsFile)) {
        $dots.Foreach($f)
    }
}


#endregion

switch ($Mode) {
    Update { Expand-DotFiles -Force:$Force }
    Backup { Compress-DotFiles }
    default { Write-Error $message.What }
}