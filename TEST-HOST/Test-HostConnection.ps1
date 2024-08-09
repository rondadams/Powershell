<#
.SYNOPSIS
    Test Host Connection status
.DESCRIPTION
    Tests DNS and Ping status for given Host(s)
    Can also check Windows RDP (port 3389) and any other port with optional parameters. 
.PARAMETER Hosts
    Name of Host(s) to check
    Single, or multiple, separated by comma, alternatively can be a file name with a list.
.PARAMETER Port
    Checks Specified Port 
.PARAMETER ProgressBar
    Shows progress bar indicator 
.NOTES
    Name       : Test-HostConnection
    Author     : Tripwire Professional Services
    Version    : 1.4
    DateCreated: 2019-05-04
    1.4 - Fix logic for Ping & Port checking where it would only check one, not both
          Correct issues with checking when Test-NetConnection cmdlet not found
          Changed status return values for Ping & Port to True/False
          Removed RDPPing parameter
    1.3 - Added Progress Bar.
    1.2 - Added Multi-threading (jobs) to speed up process.
    1.1 - Added options for including RDP or select port. 
.EXAMPLE
    Test-Host -Hosts 'Hostname' 
.EXAMPLE
    Test-Host.ps1 (Import-Csv .\Hosts.csv -Header "Hostname") | Format-Table
#>

[CmdletBinding(DefaultParameterSetName="set1")]
Param(
    [Parameter(ParameterSetName="set1", Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [Parameter(ParameterSetName="set2", Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [ValidateNotNullOrEmpty()]
    [array]$Hosts,

    [Parameter(ParameterSetName="set2", Mandatory = $false)]
    [string]$Port,

    [Parameter(ParameterSetName="set1", Mandatory = $false)]
    [Parameter(ParameterSetName="set2", Mandatory = $false)]
    [switch]$ProgressBar=$false
    )


Begin {

    #$DebugPreference = "Continue"
    #$VerbosePreference = "Continue"

    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    #Write-Verbose (Get-Date)
    
    $ErrorActionPreference = 'SilentlyContinue'
    $i = $Cnt = $Pct = 0
} 

Process {
    
    $ScriptBlock = {
        Param($Hostn,$RDPPing,$Port)

        if ([bool]($Hostn -as [ipaddress])) {
            $nslkup = ([system.net.dns]::GetHostByAddress([ipaddress]$Hostn)) #.Hostname
        }
        else {
            $nslkup = ([System.Net.DNS]::GetHostEntry("$Hostn"))  #(Resolve-DnsName -Name $Hostn)
        } # nslkup

        $ping = (Test-Connection -ComputerName $Hostn -Count 1 -ErrorAction SilentlyContinue)
        if ($ping) {
            $pingstat = "True" 
        }
        else { 
            $pingstat = "False" 
        }

        if (![string]::IsNullOrEmpty($Port)) {
            $portping = New-Object System.Net.Sockets.TcpClient($Hostn, $port)
            if (!$portping) { $portpingstat = $false }
            else { $portpingstat = $true }
            $Output = [pscustomobject]@{
                HostName = $Hostn
                IPAddr = $ping.IPV4Address
                Ping = $pingstat
                "Port$Port" = $portpingstat
                DNSName = $nslkup.Hostname
                }
            }
        else {
            $Output = [pscustomobject]@{
                    HostName = $Hostn
                    IPAddr = $ping.IPV4Address
                    Ping = $pingstat
                    DNSName = $nslkup.Hostname
                    }
            }
        return $Output
    } # $ScriptBlock    
  
    foreach ($Hostx in $Hosts) {
        $Hostx = $Hostx.Trim()
        if (!$Hostx) {continue}
        if ($ProgressBar) {
            $i++
            $pct = (($i / $Hosts.Count) * 100)
            $Cnt = $Hosts.Count
            Write-Progress -Activity "Starting Background Job for $Hostx " -PercentComplete $pct -Status "$i of $Cnt"
            }
        while ((get-job -Name $Hostx -ErrorAction SilentlyContinue).count -eq 0) {
            if ((get-job -State Running).count -lt 15) {
                Write-Verbose "Starting Background Job for $Hostx" 
                start-job -Name $Hostx -ScriptBlock $ScriptBlock -ArgumentList ($Hostx,$RDPPing,$Port) | Out-Null
                }
            else {
                sleep -s 1
                }
        } # while 
    } # foreach 
} # End Process

End {
    #Get all job results
    Write-Verbose "Waiting for background jobs to complete..." 
    foreach ($job in (Get-Job | Wait-Job)) {
      if($job.state -eq 'Completed') {
          Write-Output (Receive-Job -Id $job.id -Wait -AutoRemoveJob | Select-Object * -ExcludeProperty RunspaceId, PSSourceJobInstanceid, PSComputerName,PSShowComputerName) 
        } 
    } # foreach $job

	Get-Job
    #Get-Job | Remove-Job -Force

    $Stopwatch.Stop | Out-Null
    Write-Verbose ($Stopwatch.Elapsed.TotalSeconds)
        
    Return
}