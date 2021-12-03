using namespace System.IO
using namespace System.Collections.Generic
using namespace System.Management.Automation

param(
    [Parameter(
        Mandatory,
        HelpMessage = 'Enter a mode, Update or Backup')]
    [ValidateSet('Update', 'Backup', 'Debug')]
    [string] $Mode
    ,
    [switch] $Force
) 

#region Data and Literals ------------------------------------------------------
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
        ShouldProcess = @{
            ExportDotFile = 'Export dot entries?'
        }
        Sourced = 'The dots script has been sourced.'
    }
}

data Setting {
    @{
        ArchivePath = 'dots.xml'
        ErrorActionPreference = 'Continue'
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

#endregion

#region Classes ----------------------------------------------------------------


class DotEntry {
    [string[]] $Content
    [scriptblock] $CompressCommand 
    [scriptblock] $ExpandCommand

    DotEntry([scriptblock] $ExpandCommand, [scriptblock] $CompressCommand, [string[]] $Content) {
        $this.ExpandCommand = $ExpandCommand
        $this.CompressCommand = $CompressCommand
        $this.Content = $Content
    }

    DotEntry([scriptblock] $ExpandCommand, [scriptblock] $CompressCommand) {
        $this.ExpandCommand = $ExpandCommand
        $this.CompressCommand = $CompressCommand
        $this.Content = $null
    }

    DotEntry([hashtable] $x) {
        $this.Content = 
            if ($x.ContainsKey('Content')) {
                $x.Content
            }
            else {
                $null
            }
        $this.ExpandCommand = $x.ExpandCommand
        $this.CompressCommand = $x.CompressCommand
    }

    [void] SetContent($Content) {
        $this.Content = $Content
    }

    [void] Compress() {
        $this.Content = $this.CompressCommand.Invoke()
    } 

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


class DotFile : DotEntry {
    [string] $Target
    [string] $ExpandedTarget
    [FileInfo] $TargetObject

    DotFile([string] $Target) { 
        $this.Target = $Target

        $this.ExpandTarget()

        if ($this.TargetObject.Exists) {
            $this.CompressCommand = { Get-Content -Path $this.TargetObject.FullName -Verbose }
        }
    } 

    DotFile([string] $Target, [string[]] $Content) {
        $this.Content = $Content
        $this.Target = $Target

        $this.ExpandTarget()

        if ($this.TargetObject.Exists) {
            $this.CompressCommand = { Get-Content -Path $this.TargetObject.FullName -Verbose }
        }
    }

    DotFile([hashtable] $x) {
        $this.Target = $x.Target
        $this.Content = 
            if ($x.ContainsKey('Content')) {
                $x.Content
            }
            else {
                $null
            }

        $this.ExpandTarget()

        if ($this.TargetObject.Exists) {
            $this.CompressCommand = { Get-Content -Path $this.TargetObject.FullName -Verbose }
        }
    }

    [void] Expand() { }  # Do nothing

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
            @{
                Content = $this.Content
                Path = $this.TargetObject.FullName
            }
            # $this.Content | Out-File (New-Item $this.TargetObject.FullName -Force) -Encoding UTF8 -Verbose
        }
    }

    hidden [void] ExpandTarget() {
        $sb = [scriptblock]::Create($this.Target)
        $this.ExpandedTarget = $sb.Invoke()
        $this.TargetObject = $this.ExpandedTarget -as [FileInfo]
    }
}



# A do-nothing converter, just to hide the "object" methods
class PSObjectConverter : System.Management.Automation.PSTypeConverter {
    [bool] CanConvertFrom([PSObject]$psSourceValue, [Type]$destinationType) {
        return $false
    }

    [object] ConvertFrom([PSObject]$psSourceValue, [Type]$destinationType, [IFormatProvider]$formatProvider, [bool]$ignoreCase) {
        throw [NotImplementedException]       
    }

    # These things down here are just never used. Why they must be here, I have no idea.
    [bool] CanConvertFrom([object]$sourceValue, [Type]$destinationType) {
        return $false
    }

    [object] ConvertFrom([object]$sourceValue, [Type]$destinationType, [IFormatProvider]$formatProvider, [bool]$ignoreCase) {
        throw [NotImplementedException]
    }

    [bool] CanConvertTo([object]$sourceValue, [Type]$destinationType) {
        throw [NotImplementedException]
    }

    [object] ConvertTo([object]$sourceValue, [Type]$destinationType, [IFormatProvider]$formatProvider, [bool]$ignoreCase) {
        throw [NotImplementedException]
    }
}


class DotFileConverter : PSObjectConverter {
    [bool] CanConvertFrom([PSObject] $psSourceValue, [Type] $destinationType) {
        return $psSourceValue.PSTypeNames.Contains("Deserialized.DotFile")
    }

    [object] ConvertFrom([PSObject] $psSourceValue, [Type] $destinationType, [IFormatProvider] $formatProvider, [bool] $ignoreCase) {
        return [DotFile] @{
            Target = $psSourceValue.Target
            Content = $psSourceValue.Content
        }
    }
}


class DotEntryConverter : PSObjectConverter {
    [bool] CanConvertFrom([PSObject] $psSourceValue, [Type] $destinationType) {
        return $psSourceValue.PSTypeNames.Contains("Deserialized.DotEntry")
    }

    [object] ConvertFrom([PSObject] $psSourceValue, [Type] $destinationType, [IFormatProvider] $formatProvider, [bool] $ignoreCase) {
        return [DotEntry] @{
            ExpandCommand = [scriptblock]::Create($psSourceValue.ExpandCommand)
            CompressCommand = [scriptblock]::Create($psSourceValue.CompressCommand)
            Content = $psSourceValue.Content
        }
    }
}

Update-TypeData -TypeName 'Deserialized.DotEntry' -TargetTypeForDeserialization 'DotEntry'
Update-TypeData -TypeName 'Deserialized.DotFile' -TargetTypeForDeserialization 'DotFile'
Update-TypeData -TypeName 'DotEntry' -TypeConverter 'DotEntryConverter'
Update-TypeData -TypeName 'DotFile' -TypeConverter 'DotFileConverter'

#endregion

#region Config -----------------------------------------------------------------

function New-Scriptblock {
    [Alias('Get-Scriptblock')]
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

#endregion

#region Setup ------------------------------------------------------------------ 
$Config.PathVariable.GetEnumerator().ForEach{
    $p = [Scriptblock]::Create($_.Value)
    $v = $p.Invoke() -as [string]
    
    Set-Variable $_.Key $v -Option ReadOnly
}

$File = $Config.Path.ForEach{ [DotFile] $_ }
$Command = $Config.Command.ForEach{
    [DotEntry] @{
        CompressCommand = Scriptblock $_.Compress
        ExpandCommand = Scriptblock $_.Expand
    }
} 
$Entry = [DotEntry[]] @($File + $Command)


function Import-DotFile {
    [CmdletBinding()]

    param(
        # Specifies a path to one existing location.
        [Parameter(Mandatory,
                   ValueFromPipeline,
                   ValueFromPipelineByPropertyName,
                   HelpMessage = 'Path to one valid location.')]
        [Alias('Path', 'PSPath')]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            if (Test-Path $_) {
                return $true
            }

            throw 'Invalid file.'
        })]
        [string] $InputObject
    )

    process {
        $raw = Get-Content -Raw -Encoding UTF8 -Path $InputObject

        [PSSerializer]::Deserialize($raw)
    }
}


function Export-DotFile {
    [CmdletBinding(SupportsShouldProcess)]

    param(
        # Specifies a path to one valid location.
        [Parameter(Mandatory,
                   HelpMessage = 'Path to one valid location.')]
        [Alias('PSPath')]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            if (Test-Path -IsValid $_) {
                return $true
            }

            throw 'Invalid location'
        })]
        [string] $Path
        ,
        [Parameter(ValueFromPipeline,
                   ValueFromPipelineByPropertyName)]
        [DotEntry[]] $InputObject
    )
    
    begin {
        $a = [List[DotEntry]] @()
        $f = { 
            [void] $a.Add($_)
        }
    }

    process {
        $InputObject.ForEach($f)
    }

    end {
        if ($PSCmdlet.ShouldProcess($Path, $Message.ShouldProcess.ExportDotFile)) {
            [PSSerializer]::Serialize($a.ToArray()) | Out-File $Path -Encoding utf8 -Verbose
        }
    }
}


function Compress-DotEntry {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline,
                   ValueFromPipelineByPropertyName)]
        [DotEntry[]] $InputObject
    )
    
    begin {
        $a = [List[DotEntry]] @()
        $f = {
            if ($null -ne $_.CompressCommand) { $_.Compress() } 
        }
        $g = {
            [void] $a.Add($_)
        }
    }
    
    process {
        $InputObject.ForEach($f).ForEach($g)
    }
    
    end {
        $a.ToArray()
    }
}


function Expand-DotEntry {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline,
                   ValueFromPipelineByPropertyName)]
        [DotEntry[]] $InputObject
        ,
        [switch] $Force
    )
    
    begin {
        $a = [List[DotEntry]] @()
        $f = {
            if ($Force.IsPresent) {
                $_.Expand($true)
            }
            else {
                $_.Expand($false)
            }
        }
        $g = {
            [void] $a.Add($_)
        }
    }
    
    process {
        $InputObject.ForEach($f).ForEach($g)
    }
    
    end {
        $a.ToArray()
    }
}

#endregion

switch ($Mode) {
    Update { Expand-DotFiles -Force:$Force }
    Backup { Compress-DotFiles }
    Debug { Write-Output $Message.Sourced }
    default { Write-Error $Message.TerminatingError.What }
}