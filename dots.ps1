using namespace System.IO
using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.Management.Automation

param(
    [Parameter(
        Mandatory,
        HelpMessage = 'Enter a mode, Push to the archive, Pull from the archive, or Sync latest changes?')]
    [ValidateSet('Pull', 'Push', 'Debug', 'Sync')]
    [string] $Mode
    ,
    [ValidateSet('File', 'Entry', 'Both')]
    [string] $DotType = 'File'
    ,
    [switch] $Select
    ,
    [switch] $Force
) 

#region Data and Literals ------------------------------------------------------
data Message {
    @{
        InvalidConfig    = '''{0}'' {1} not a valid config key. Valid keys are: {2}'
        TerminatingError = @{
            ConfigNotFound = 'Fatal: config file ''{0}'' not found or invalid!'
            What           = 'Fatal: you somehow reached the unreachable!'
            Wip            = 'Work in progress: Not implemented yet!'
        } 
        ShouldContinue   = @{
            ExpandDotFiles  = 'Continue? This will likely overwrite your dot files; backup recommended.'
            CompressDotFile = 'Continue? You will overwrite the dotfile archive.'
        }
        ShouldProcess    = @{
            ExportDotFile = 'Export dot entries'
        }
        Warning          = @{
            TypeDateAlreadyDeclared = 'TypeData seems to be already declared for my internal types.'
        }
        Sourced          = 'The dots script has been sourced.'

        Menu             = @{
            Empty   = 'Nothing was passed to ''Invoke-Menu''' 
            TooMany = 'The incoming array has more items than the console window can display! Damn.'
            Exit    = 'Press any key to exit...'
        }
    }
}

data Setting {
    @{
        ArchivePath           = 'dots.xml'
        ErrorActionPreference = 'Continue'
        VerbosePreference     = 'Continue'
        BindingVariable       = 'Config'
        FileName              = 'dots.config.psd1'
        MenuKeys              = @{
            MoveDownKey        = 38, 75
            MoveUpKey          = 40, 74
            SelectItemKey      = 32
            ReturnSelectionKey = 13
            ExitKey            = 27, 81
        }
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
    'Description'
}

data IsAre {
    'is'
    'are'
}

data Character {
    @{
        Space      = ' '
        CommaSpace = ', '
        CheckMark  = '✔'
        Current    = '►'
    }
}


$ErrorActionPreference = $Setting.ErrorActionPreference
$VerbosePreference = $Setting.VerbosePreference

Join-Path $PSScriptRoot $Setting.ArchivePath | Set-Variable DotsFile -Option ReadOnly

#endregion

#region Helpers ---------------------------------------------------------------


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


function Assert-Config ($x, $y) {
    $xs = [HashSet[string]] $x
    $ys = [HashSet[string]] $y

    if (!$xs.IsSubsetOf($ys)) {
        [void] $xs.ExceptWith($ys) 

        $isAre = $IsAre[$xs.Count -gt 1]

        throw ($Message.InvalidConfig -f ($xs -join $Character.CommaSpace),
            $isAre,
            ($ys -join $Character.CommaSpace)) 
    } 
}


# Console Helper Functions ----------------------------------------------------
function CenterString ($s) {
    $x = $Host.UI.RawUI.BufferSize.Width
    $s.PadLeft(((($x - 1) - $s.Length) / 2) + $s.Length).PadRight($x - 1)
}

function WriteColorString ($s, [ConsoleColor] $c) {
    $oc = [Console]::ForegroundColor
    [Console]::ForegroundColor = $c 
    [Console]::WriteLine($s) 
    [Console]::ForegroundColor = $oc
}

function WriteColorStringSegment ($s, [ConsoleColor] $c) {
    $oc = [Console]::ForegroundColor
    [Console]::ForegroundColor = $c 
    [Console]::Write($s) 
    [Console]::ForegroundColor = $oc
}

function CursorOff { [Console]::CursorVisible = $false }
function CursorOn { [Console]::CursorVisible = $true }
function GetKeyPress { $Host.UI.RawUI.ReadKey('NoEcho, IncludeKeyDown') } 
function Await { GetKeyPress > $null }
function ConsoleWrite ($s) { [Console]::Write($s) }
function WriteLine ($s) { [Console]::WriteLine($s) }
function SetCursorPosition ($x, $y) { [Console]::SetCursorPosition($x, $y) } 
function HalfWindowHeight { [int] [Console]::WindowHeight / 2 }
function WindowHeight { [int] [Console]::WindowHeight }
function BufferWidth { [Console]::BufferWidth }
function ClearConsoleRow ($n) { SetCursorPosition 0 $n; ConsoleWrite ($Character.Space * (BufferWidth)) }
function CursorTop { [Console]::CursorTop }
function EvenSpace ($n) { [int] [Console]::WindowWidth / $n }


#region Classes ----------------------------------------------------------------


class Dot {
    [string[]] $Content
    [scriptblock] $CompressCommand 
    [scriptblock] $ExpandCommand

    [void] SetContent([string[]] $Content) {
        $this.Content = $Content
    }

    [void] Compress() {
        $this.Content = $this.CompressCommand.Invoke()
    } 
}


class DotEntry : Dot {
    [string] $Description

    DotEntry([hashtable] $x) {
        $this.Content = $x.Content
        $this.ExpandCommand = $x.ExpandCommand
        $this.CompressCommand = $x.CompressCommand
        $this.Description = $x.Description
    }

    [string] ToString() {
        return $this.Description
    }

    [void] Expand([bool] $b) {
        $this.Expand()
    }

    [void] Expand() {
        if (!$this.Content) {
            $this.ExpandCommand.Invoke()
        }
        else { 
            $this.Content.ForEach($this.ExpandCommand)
        }
    } 
}


class DotFile : Dot {
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

    DotFile([hashtable] $x) {
        $this.Target = $x.Target
        $this.Content = $x.Content

        $this.ExpandTarget()

        if ($this.TargetObject.Exists) {
            $this.CompressCommand = { Get-Content -Path $this.TargetObject.FullName -Verbose }
        }
    }

    [hashtable] Expand() { return $this.Expand($false) }

    [hashtable] Expand([bool] $force) {
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

        if ($this.TargetObject.Exists -or ($force -and $isValidPath)) {
            return @{
                InputObject = $this.Content
                LiteralPath = $this.TargetObject.FullName
            }

            # $this.Content | Out-File (New-Item $this.TargetObject.FullName -Force) -Encoding UTF8 -Verbose
        }

        return @{} 
    }

    [string] ToString() {
        return $this.TargetObject.Name
    }

    static [DotFile] Reserialize([psobject] $deserializedObject) {
        if ($deserializedObject.PSTypeNames.Contains('Deserialized.DotFile')) {
            return [DotFile] @{
                Target  = $deserializedObject.Target
                Content = $deserializedObject.Content
            }
        }

        return [DotFile] @{}
    }

    hidden [void] ExpandTarget() {
        $sb = New-Scriptblock $this.Target
        $this.ExpandedTarget = $sb.Invoke()
        $this.TargetObject = $this.ExpandedTarget -as [FileInfo]
    }
}



# A do-nothing converter.
# This technique was demonstrated by Jaykul
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


class DotEntryConverter : PSObjectConverter {

    [bool] CanConvertFrom([psobject] $psSourceValue, [type] $destinationType) {
        return $psSourceValue.PSTypeNames.Contains('Deserialized.DotEntry')
    }

    [object] ConvertFrom(
        [psobject] $psSourceValue, 
        [type] $destinationType, 
        [IFormatProvider] $formatProvider, 
        [bool] $ignoreCase) {

        $obj = [DotEntry] @{
            Content         = $psSourceValue.Content
            Description     = $psSourceValue.Description
            CompressCommand = New-Scriptblock $psSourceValue.CompressCommand
            ExpandCommand   = New-Scriptblock $psSourceValue.ExpandCommand
        }

        return $obj
    }
}


class DotFileConverter : PSObjectConverter {

    [bool] CanConvertFrom([psobject] $psSourceValue, [type] $destinationType) {
        return $psSourceValue.PSTypeNames.Contains('Deserialized.DotFile')
    }

    [object] ConvertFrom(
        [psobject] $psSourceValue, 
        [type] $destinationType, 
        [IFormatProvider] $formatProvider, 
        [bool] $ignoreCase) {

        $obj = [DotFile] @{
            Target  = $psSourceValue.Target
            Content = $psSourceValue.Content
        }

        return $obj 
    }
}

Update-TypeData -TypeName Deserialized.DotEntry -TargetTypeForDeserialization DotEntry -Force
Update-TypeData -TypeName Deserialized.DotFile -TargetTypeForDeserialization DotFile -Force
Update-TypeData -TypeName DotEntry -TypeConverter DotEntryConverter -Force
Update-TypeData -TypeName DotFile -TypeConverter DotFileConverter -Force

#endregion

#region Config -----------------------------------------------------------------
$ConfigFile = @{
    BindingVariable = $Setting.BindingVariable
    BaseDirectory   = $PSScriptRoot
    FileName        = $Setting.FileName
}

try {
    Import-LocalizedData @ConfigFile
    # Assert-Config ($Config.Keys -as [string[]]) $Validation
    # Assert-Config ($Config.Command.Keys -as [string[]]) $CommandValidation
    Assert-Config @($Config.Keys) $Validation
    Assert-Config @($Config.Command.Keys) $CommandValidation
} 
catch { 
    Write-Error $_ -ErrorAction Continue 
    Write-Error ($Message.TerminatingError.ConfigNotFound -f $ConfigFile.FileName) 
}

#endregion

#region Setup ------------------------------------------------------------------ 


function Get-Dots {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param(
        [Parameter(ParameterSetName = 'File')]
        [Alias('DotFile')]
        [switch] $FileOnly
        ,
        [Parameter(ParameterSetName = 'Entry')]
        [Alias('DotEntry')]
        [switch] $CommandOnly
    )


    $Config.PathVariable.GetEnumerator().ForEach{
        $p = New-Scriptblock $_.Value
        $v = $p.Invoke() -as [string]
    
        Set-Variable $_.Key $v -Option ReadOnly
    }

    $File = $Config.Path.ForEach{ [DotFile] $_ }
    $Command = $Config.Command.ForEach{
        [DotEntry] @{
            Description     = $_.Description
            CompressCommand = New-Scriptblock $_.Compress
            ExpandCommand   = New-Scriptblock $_.Expand
        }
    } 

    switch ($PSCmdlet.ParameterSetName) {
        File { [Dot[]] @($File) }
        Entry { [Dot[]] @($Command) }
        default { [Dot[]] @($File + $Command) }
    } 
}



function Import-DotFile {
    [CmdletBinding(DefaultParameterSetName = 'Default')]

    param(
        # Specifies a path to one existing location.
        [Parameter(
            Position = 0,
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            HelpMessage = 'Path to one valid location.')]
        [Alias('Path', 'PSPath')]
        [ValidateNotNullOrEmpty()]
        [ValidateScript( {
                if (Test-Path $_) {
                    return $true
                }

                throw 'Invalid file.'
            })]
        [string] $InputObject
        ,
        [Parameter(ParameterSetName = 'File')]
        [Alias('DotFile')]
        [switch] $FileOnly
        ,
        [Parameter(ParameterSetName = 'Entry')]
        [Alias('DotEntry')]
        [switch] $CommandOnly
    )
    
    begin {
        $isFile = { $_ -is [DotFile] }
        $isEntry = { $_ -is [DotEntry] }
    }
    
     
    process {
        $raw = Get-Content -Raw -Encoding UTF8 -Path $InputObject

        # [PSSerializer]::Deserialize($raw)

        switch ($PSCmdlet.ParameterSetName) {
            File { [PSSerializer]::Deserialize($raw).Where($isFile) }
            Entry { [PSSerializer]::Deserialize($raw).Where($isEntry) }
            default { [PSSerializer]::Deserialize($raw) }
        }
    }
}


function Export-DotFile {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]

    param(
        # Specifies a path to one valid location.
        [Parameter(
            Mandatory,
            HelpMessage = 'Path to one valid location.')]
        [Alias('PSPath')]
        [ValidateNotNullOrEmpty()]
        [ValidateScript( {
                if (Test-Path -IsValid $_) {
                    return $true
                }

                throw 'Invalid location.'
            })]
        [string] $Path
        ,
        [Parameter(
            ValueFromPipeline,
            ValueFromPipelineByPropertyName)]
        [Dot[]] $InputObject
    )
    
    begin {
        $a = [List[Dot]] @()
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
        [Parameter(
            ValueFromPipeline,
            ValueFromPipelineByPropertyName)]
        $InputObject
    )
    
    begin {
        $f = {
            if ($null -ne $_.CompressCommand) { $_.Compress() } 

            $_
        }
    }
    
    process {
        $InputObject.ForEach($f)
    }
}


function Expand-DotEntry {
    [CmdletBinding()]
    param (
        [Parameter(
            ValueFromPipeline,
            ValueFromPipelineByPropertyName)]
        $InputObject
        ,
        [switch] $Force
    )
    
    begin {
        $f = {
            if ($Force.IsPresent) {
                $_.Expand($true)
            }
            else {
                $_.Expand($false)
            }

            # $_
        }
    }
    
    process {
        $InputObject.ForEach($f)
    }
}


function Invoke-Menu {
    <#
    .Synopsis
      Invokes a command-line selection menu 
    #>

    [CmdletBinding()]
    param (
        # The incoming objects to choose from.
        [Parameter(
            ValueFromPipeline,
            ValueFromPipelineByPropertyName)]
        [AllowEmptyCollection()]
        [array] $InputObject
        ,
        [Parameter(Position = 0)]
        [string] $Title = 'Menu'
    )

    begin {
        # Create lists
        $menuItems = [ArrayList] @()
        $selection = [List[int]] @()

        # Grab the console screen contents to restore later
        $x = $Host.UI.RawUI.BufferSize.Width
        $y = $Host.UI.RawUI.CursorPosition.Y
        $z = [System.Management.Automation.Host.Rectangle]::new(0, 0, $x - 1, $y)
        $o = [System.Management.Automation.Host.Coordinates]::new(0, 0)
        $conBuffer = $Host.UI.RawUI.GetBufferContents($z)         

        # The key being pressed
        $vKeyCode = 0

        # The row relative position in the console buffer
        $pos = 0 
        
        $add = {
            [void] $menuItems.Add($_)
        }
 
        # Menu Helpers 

        # I didn't want to use a class, but this little guy made lazy redrawing easier.
        class Row {
            [int] $Row
            [string] $String
            [ConsoleColor] $Color
            [bool] $Current
            [bool] $Selected 

            Row([int] $n) {
                $this.Row = $n
                $this.Color = [ConsoleColor]::Magenta
                $this.Current = $false
                $this.Selected = $false
            }

            [void] SetString($s) {
                $this.String = $s
            }

            [void] ToggleSelect() {
                $this.Selected = !$this.Selected
            }

            [void] ToggleCurrent() { 
                $this.Current = !$this.Current
                
                if ($this.Current) {
                    $this.Color = [ConsoleColor]::Cyan

                    return
                }

                $this.Color = [ConsoleColor]::Magenta 
            }

            [void] Draw() {
                ClearConsoleRow $this.Row

                if ($this.Current) {
                    SetCursorPosition 1 $this.Row
                    ConsoleWrite '>'
                }

                if ($this.Selected) {
                    SetCursorPosition 3 $this.Row
                    ConsoleWrite '-'
                }

                SetCursorPosition 5 $this.Row
                WriteColorString $this.String $this.Color 
            }
        }
  
        
        # Pegs the row index to relative pos for accurate selections
        # Then maps a new row array from the inputobjects and returns the rows
        function GetRows ($startRow) {
            $index = 0 
            $rowIndex = $startRow

            foreach ($item in $menuItems) {
                $row = [Row] $rowIndex

                $row.SetString($item.ToString())

                if ($pos -eq $index) {
                    $row.ToggleCurrent()
                }

                if ($selection.Contains($index)) {
                    $row.ToggleSelect()
                } 

                $index++
                $rowIndex++

                $row
            }
        }

        function SelectRow ($rows, $n) { $row = $rows[$n]; $row.ToggleSelect() } 
        function ToggleRow ($rows, $n) { $row = $rows[$n]; $row.ToggleCurrent() } 
        function DrawRow ($rows, $n) { $row = $rows[$n]; $row.Draw() } 

        function ToggleSelection ($n) {
            if ($selection.Contains($n)) {
                [void] $selection.Remove($n)

                return
            }

            $selection.Add($n) 
        }

        function ResetPositionOnOverflow ($ls, $pos) {
            if ($pos -lt 0) { $pos = $ls.Count - 1 }
            if ($pos -gt $ls.Count - 1) { $pos = 0 } 

            $pos
        }

        function ExitMenu { 
            Clear-Host

            $Host.UI.RawUI.SetBufferContents($o, $conBuffer)

            SetCursorPosition 0 $y
            CursorOn       
        }


        # Do some aesthetic stuff
        CursorOff
        Clear-Host
    }

    process {
        $InputObject.ForEach($add)
    }

    end {
        SetCursorPosition 0 1 
        WriteColorString (CenterString $Title) Cyan

        if ($menuItems.Count -lt 1) {
            WriteLine (CenterString $Message.Menu.Empty)
            WriteLine
            WriteLine (CenterString $Message.Menu.Exit) 
            Await
            ExitMenu 

            return 
        }

        # Todo: It will be a lot of work, but wrap overflow horizontally so we use a 2d row col grid
        # Todo: Implement <left> and <right> keys
        # Todo: Truncate string lengths with a max col width etc...
        if ($menuItems.Count -gt (WindowHeight)) {
            WriteLine (CenterString $Message.Menu.TooMany)
            WriteLine
            WriteLine (CenterString $Message.Menu.Exit)
            Await
            ExitMenu

            return
        }
        
        $rows = GetRows 3
        $rows.ForEach('Draw')

        while ($vKeyCode -ne $Setting.MenuKeys.ReturnSelectionKey) {
            $vKeyCode = (GetKeyPress).VirtualKeyCode

            if ($Setting.MenuKeys.ExitKey -contains $vKeyCode) {
                $pos = $null

                break
            }

            switch ($vKeyCode) {
                { $Setting.MenuKeys.MoveUpKey -contains $_ } {
                    ToggleRow $rows $pos
                    DrawRow $rows $pos
                    $pos++
                    $pos = ResetPositionOnOverflow $rows $pos
                    ToggleRow $rows $pos
                    DrawRow $rows $pos 
                }
                { $Setting.MenuKeys.MoveDownKey -contains $_ } {
                    ToggleRow $rows $pos
                    DrawRow $rows $pos
                    $pos--
                    $pos = ResetPositionOnOverflow $Rows $pos  # Technically underflow...
                    ToggleRow $rows $pos
                    DrawRow $rows $pos 
                }
                { $Setting.MenuKeys.SelectItemKey -contains $_ } {
                    ToggleSelection $pos
                    SelectRow $rows $pos
                    DrawRow $rows $pos 
                }
            } 
        }

        ExitMenu 
        
        if ($null -ne $pos) {
            $menuItems[$selection.ToArray()]
        } 
    }
}

#endregion

$import = @{
    Path = $DotsFile
}

$get = @{}

switch ($DotType) {
    File { 
        $import.FileOnly = $true
        $get.FileOnly = $true
    }

    Entry {
        $import.CommandOnly = $true
        $get.CommandOnly = $true
    }

    default { }
}

function SelectOrPass {
    begin { 
        $ls = [ArrayList] @()
    }
    process {
        [void] $ls.Add($_) 
    }

    end {
        if ($Select) {
            $ls.ToArray() | Invoke-Menu ('Select Dots to {0}' -f $Mode)

            return
        }

        $ls.ToArray()
    }
}

switch ($Mode) {

    Pull { 
        Import-DotFile @import |
        SelectOrPass |
        Expand-DotEntry
    }

    Push { 
        Get-Dots @get |
        SelectOrPass |
        Compress-DotEntry |
        Export-DotFile $DotsFile 
    } 

    Sync {
        Write-Error -Exception [System.NotImplementedException] -Message $Message.TerminatingError.Wip
    } 

    # Dotter { Invoke-Dotter } 

    Debug { Write-Output $Message.Sourced }

    default { Write-Error $Message.TerminatingError.What }
}