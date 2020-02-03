<#
.DESCRIPTION
   Finds the patching LabTech log file given a computername.
.EXAMPLE
   $temp = Get-Content computers.txt | Get-LtPatchingFile | Import-LtPatchingLog
.INPUTS
   Inputs to this cmdlet can be a list of Windows computer hostnames or IPs.
.OUTPUTS
   Output from this cmdlet is a io.fileinfo object.
#>
function Get-LtPatchingFile {
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo[]])]
    Param
    (
        [Parameter(ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [Alias('Name', '__SERVER', 'CN', 'Computer')]
        [string[]]
        $ComputerName = $env:COMPUTERNAME
    )

    Begin {
        # Establish common/initial parameter values
        $WmiSplat = @{
            Class        = 'Win32_Service'
            Filter       = "Name='LtService'"
            ComputerName = $null
        }
    }
    Process {
        Foreach ($Computer in $ComputerName) {
            # Set the target device (local OK)
            $WmiSplat.Set_Item('ComputerName', $Computer)
            #Get the path from local POV
            $AgentLocalParentPath = (Get-WmiObject @WmiSplat).PathName.Trim() -replace '\\LtSvc\.exe\s.*'
            # Add file name to path for FullName
            $LocalLogPath = Join-Path $AgentLocalParentPath 'LtPatching.txt'
            # Convert to SMB Path
            $SmbLogPath = if ($Computer -ne $env:COMPUTERNAME) {
                "\\$($Computer)\$($LocalLogPath -replace ':','$')"
            }
            else {
                $LocalLogPath
            }#$SmbLogPath = if ($Computer -ne $env:COMPUTERNAME) {
            # Write object to pipeline
            Get-Item $SmbLogPath
        }#Foreach ($Computer in $ComputerName) {
    }
    End {
    }
}
<#
.DESCRIPTION
   Imports log entries from a specificly formatted LabTech log file.
.EXAMPLE
   $temp = Get-LtPatchingFile | Import-LtPatchingLog
.INPUTS
   Inputs to this cmdlet come from the Get-LtPatchingFile function.
.OUTPUTS
   Output from this cmdlet is a psobject that can be consumed by other functions where noted.
#>
function Import-LtPatchingLog {
    [CmdletBinding()]
    [OutputType([psobject])]
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [string]
        [Alias('FullName')]
        $Path
    )

    Begin {
        $ptnLtPatchingLogLine = '(\w+?)\s\sv(\d{3}\.\d{3})\s+?\-\s(\d{1,2}\/\d{1,2}\/20\d{2}\s\d{1,2}:\d{2}:\d{2}\s?[AP]?M?)\s+?-\s(.+?):::'
        $USTimeFormat = 'M/d/yyyy h:mm:ss tt'
        $UKTimeFormat = 'dd/MM/yyyy HH:mm:ss'
    }
    Process {
        Foreach ($FullName in $Path) {

            # Pull apart the Full Path to grab the computername
            $Computer = if ($FullName -match '^\\\\') {
                $FullName -replace '^\\\\' -replace '\\.*'
            }
            else {$env:COMPUTERNAME}

            # Get the log content
            $LogContent = Get-Content $FullName

            # Match the content, line by line
            $i = 0
            Foreach ($line in $LogContent) {
                $i++
                $Groups = [regex]::Match($line, $ptnLtPatchingLogLine).Groups

                # Datetime handling of unknown culture
                $strDate = ($Groups | Where-Object {$_.Name -eq 3}).Value
                Try{
                    # Try getting the date string to a datetime
                    $TimeGenerated = Get-Date $strDate -ea Stop
                }
                Catch{
                    Try{
                        # Try to force the UK time format
                        $TimeGenerated = Get-Date $strDate -Format $UKTimeFormat -ea Stop
                    }
                    Catch{
                        Try{
                            # Try to force the US time format
                            $TimeGenerated = Get-Date $strDate -Format $USTimeFormat -ea Stop
                        }
                        Catch{
                            Try{
                                # Extract the default Date/Time formatting from the remote Culture
                                $TimeGenerated = ConvertTo-RemoteDateCulture -Date (
                                    $strDate) -ComputerName $Computer -ea Stop
                            }
                            Catch{
                                # Give up, the line number is good enough
                                $TimeGenerated = $null
                            }
                        }
                    }
                }

                New-Object psobject -Property @{
                    LineNumber    = $i
                    ComputerName  = $Computer
                    Service       = [string](($Groups | Where-Object {$_.Name -eq 1}).Value)
                    Version       = [version](($Groups | Where-Object {$_.Name -eq 2}).Value)
                    TimeGenerated = $TimeGenerated
                    Message       = [string](($Groups | Where-Object {$_.Name -eq 4}).Value)
                }#New-Object psobject -Property @{
            }#Foreach ($line in $LogContent){
        }#Foreach ($item in $Path){
    }
    End {
    }
}
Export-ModuleMember -Function @('Import-LtPatchingLog','Get-LtPatchingFile')
