Function Update-CMDeviceCollection 
{ 
    <# 
    .Synopsis 
       Update SCCM Device Collection 
    .DESCRIPTION 
       Update SCCM Device Collection. Use the -Wait switch to wait for the update to complete. 
    .EXAMPLE 
       Update-CMDeviceCollection -DeviceCollectionName "All Workstations" 
    .EXAMPLE 
       Update-CMDeviceCollection -DeviceCollectionName "All Workstations" -Wait -Verbose 
    #> 

    [CmdletBinding()] 
    [OutputType([int])] 
    Param 
    ( 
        [Parameter(Mandatory=$true, 
                   ValueFromPipelineByPropertyName=$true, 
                   Position=0)] 
        $DeviceCollectionName, 
        [Switch]$Wait 
    ) 

    Begin 
    { 
        Write-Verbose "$DeviceCollectionName : Update Started" 
    } 
    Process 
    { 
        $Collection = Get-CMDeviceCollection -Name $DeviceCollectionName 
        $null = Invoke-WmiMethod -Path "ROOT\SMS\Site_AZR:SMS_Collection.CollectionId='$($Collection.CollectionId)'"  -Name RequestRefresh  
    } 
    End 
    { 
        if($Wait) 
        { 
            While($(Get-CMDeviceCollection -Name $DeviceCollectionName | Select -ExpandProperty CurrentStatus) -eq 5) 
            { 
                Write-Verbose "$DeviceCollectionName : Updating..." 
                Start-Sleep -Seconds 5 
            } 
            Write-Verbose "$DeviceCollectionName : Update Complete!" 
        } 
    } 
} 


Function Verify-CCHEval {
    Param(

    [Parameter(Mandatory = $true)][string]$computername
    )    

    $EvalOK= 'Updating MDM_ConfigSetting.ClientHealthStatus with value 7'
    $Lastline = gc "filesystem::\\$computername\C$\windows\ccm\logs\CcmEval.log"|select -skiplast 1|select -last 1
    If ($lastline -match $EvalOK) {
        $true
    } Else {
        $false
    }
}

cd hq1:
ipconfig /flushdns|out-null

$coll = "Currently offline Windows 10 clients" 
$i=1
Update-CMDeviceCollection -DeviceCollectionName $coll -Wait -Verbose 
$Targets = Get-CMCollectionMember -CollectionName $coll |sort name
$Total = $Targets.Count

$results =@()
ForEach ($target in $targets) {
    $c=$target.name
    Write-host "Pinging $c ($i/$Total)" -foregroundcolor White
    $i+=1
    If (Test-Connection $c -quiet -count 1) {
        Write-host "`t$c is ONLINE.  Running CCMEval" -foregroundcolor cyan
        $OnlineStatus = "Online"
        TRy {
            Invoke-Command -computername $c -scriptblock {start-process "c:\windows\ccm\ccmeval.exe" -Wait}  -ea Stop
            $CCMEValCheck = Verify-CCHEval -computername $c
            If ( $CCMEValCheck -eq $false){
                Write-Host "`tCCM Client is in error.  Reinstalling client" -foregroundcolor yellow
                $ClientStatus = "Error"
                Invoke-Command -ComputerName $c -ScriptBlock {
                    Start-Process c:\windows\ccmsetup\ccmsetup.exe -ArgumentList '/mp:contoso.com /forceinstall SMSSITECODE=XXX /BITSPriority:FOREGROUND' -wait
                }

            } Else {
                Write-Host "`tCCM Client is OK" -foregroundcolor green

                $ClientStatus = "OK"
            }
        }
        Catch {
            Write-host "`tFailed to run CCMEVAL on $c" -foregroundcolor red
            $ClientStatus = "Unknown (Could not run CCMEval)"
        }
    } Else {
        $OnlineStatus = "Offline"
        $ClientStatus = "Offline"

    }
    $results += [pscustomobject] @{
        Computer = $c
        Status = $OnlineStatus
        ClientState = $ClientStatus 

    }
}
$results|Where ClientState -eq "Error"