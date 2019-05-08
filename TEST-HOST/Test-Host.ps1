<#
.SYNOPSIS
    Test Host status
.DESCRIPTION
    Tests DNS and Ping status for given Host(s)
    Can also check Windows RDP (port 3389) and any other port with optional parameters. 
.PARAMETER Hosts
    Name of Hosts to check
.PARAMETER RDPPing
    Checks Windows RDP Port 3389 
    WARNING: This slows the check significantly! 
.PARAMETER Port
    Checks Specified Port 
.PARAMETER ProgressBar
    Shows progress bar indicator 
.NOTES
    Name       : Test-Host
    Author     : Ron Adams
    Version    : 1.2
    DateCreated: 2019-05-04
    1.2 - Added Multi-threading (jobs) to speed up process.
    1.1 - Added options for including RDP or select port. 
.EXAMPLE
    Test-Host -Hosts 'Hostname' 
.EXAMPLE
    Test-Host.ps1 (Import-Csv .\Hosts.csv -Header "Hostname") | Format-Table
.EXAMPLE
    Test-Host -Hosts 'Hostname' -RDPPing 
    Checks RDP port 3389 for Host(s)
#>

[CmdletBinding(DefaultParameterSetName="set1")]
Param(
    [Parameter(ParameterSetName="set1", Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [Parameter(ParameterSetName="set2", Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [ValidateNotNullOrEmpty()]
    [array]$Hosts,

    [Parameter(ParameterSetName="set1", Mandatory = $false)]
    [switch]$RDPPing=$false,

    [Parameter(ParameterSetName="set2", Mandatory = $false)]
    [string]$Port,

    [Parameter(ParameterSetName="set1", Mandatory = $false)]
    [Parameter(ParameterSetName="set2", Mandatory = $false)]
    [switch]$ProgressBar=$false
    )

Begin {

    #$DebugPreference = "Continue"
    #$VerbosePreference = "Continue"
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
        if ($RDPPing) {
            $ping = (Test-NetConnection -ComputerName $Hostn -CommonTCPPort RDP -WarningAction SilentlyContinue)
            $Output = [pscustomobject]@{
                HostName = $Hostn
                IPAddr = $ping.RemoteAddress
                Ping = $ping.PingSucceeded
                RDP = $ping.TcpTestSucceeded
                DNSName = $nslkup.Hostname
                }
        } # RDPPing
        elseif ($Port) {
            $ping = (Test-NetConnection -ComputerName $Hostn -Port $Port -WarningAction SilentlyContinue)
            $Output = [pscustomobject]@{
                HostName = $Hostn
                IPAddr = $ping.RemoteAddress
                Ping = $ping.PingSucceeded
                "Port$Port" = $ping.TcpTestSucceeded
                DNSName = $nslkup.Hostname
                }
            }
        else {
            $ping = (Test-Connection -ComputerName $Hostn -Count 1 -ErrorAction SilentlyContinue)
            if ($ping) {
                $pingstat = "Succeeded" 
                }
            else { 
                $pingstat = "Request Timeout" 
                }
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
                Write-Debug "Starting Background Job for $Hostx" 
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
    Write-Debug "Waiting for background jobs to complete..." 
    foreach ($job in (Get-Job | Wait-Job)) {
      if($job.state -eq 'Completed') {
          Write-Output (Receive-Job -Id $job.id -Wait -AutoRemoveJob | Select-Object * -ExcludeProperty RunspaceId, PSSourceJobInstanceid, PSComputerName,PSShowComputerName) 
        } 
    } # foreach $job

    Get-Job | Remove-Job -Force
}