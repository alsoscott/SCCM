<#
.SYNOPSIS
    Run actions and/or clear cache against localhost, individual remote device, or SCCM collection of devices.

.DESCRIPTION
    This is a Powershell script to run actions and/or clear cache against localhost, individual remote device, or collection of devices.
    Disclaimer: This script is provided "AS IS" with no warranties, confers no rights and is not supported by the author.

    Author - Scott Churchill
    Contact - Various places on internet as AlsoScott

.EXAMPLE
Common Examples with desired results - for Local Device:
.\SCCM_Client_Actions.ps1
    (runs client actions against localhost)

.\SCCM_Client_Actions.ps1 -ClearCache
    (runs client actions and clears SCCM Cache against localhost)
.EXAMPLE
Common Examples with desired results - for single remote device:
.\SCCM_Client_Actions.ps1 -device <device name>
    (runs client actions against <remote device>)

.\SCCM_Client_Actions.ps1 -device <device name> -ClearCache
    (clears cache and runs actions against <remote device>)

.\SCCM_Client_Actions.ps1 -force -device <device name>
    (bypasses online check for remote device)
.EXAMPLE
Common Examples with desired results - for targeting an SCCM Collection:
.\SCCM_Client_Actions.ps1 -CollectionID <collection ID>
    (runs actions against SCCM <collection ID>)

.\SCCM_Client_Actions.ps1 -CollectionID <Collection ID> -ClearCache
    (clears cache and Runs actions against SCCM <Collection ID>)

.\SCCM_Client_Actions.ps1 -CollectionID <Collection ID> -ClearCache -force
    (bypasses online check, clears cache and runs actions against SCCM <Collection ID>)


.NOTES
    Created:    June 1st 2019
    Version:    1.2

Update 8 July
    Added machine policy purge option. Use -ResetMachinePolicy switch (this is experimental, doesn't work all the time)
    Added looping capabilities for localhost

Update: 21 June 2019
    Added Force param to bypass online checkes (some devices are online, but ICMP is blocked by network config)
    Added Clear Cache function
    
Update: 1 June 2019
    Creatied initial script - took initial client actions script, added remote functionality, added SCCM Collection polling

#>

#parameters, none are required.
param($device,$CollectionID,[switch]$Actions,[switch]$ClearCache,[switch]$Force,[switch]$WSUS,[switch]$ResetMachinePolicy,[int]$loop)
# SCCM Site configuration
$SiteCode = "" # Site code 
$ProviderMachineName = "" # SMS Provider machine name

function Actions{
    param ($device)
    if ($ClearCache){clearcache -device $device}
    if ($ResetMachinePolicy -eq $true){ResetMachinePolicy -device $device}
    #if ($Actions){
        try{
            Write-Host -ForegroundColor Yellow "Running actions on $device"
            #Discovery Data Collection Cycle
                Invoke-WMIMethod -ComputerName $device -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000003}" | Out-Null    
            #Machine Policy Retrieval Cycle
                Invoke-WMIMethod -ComputerName $device -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000021}" | Out-Null
            #Machine Policy Evaluation Cycle
                Invoke-WMIMethod -ComputerName $device -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000022}" | Out-Null
            #Application Deployment Evaluation Cycle
                Invoke-WMIMethod -ComputerName $device -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000121}" | Out-Null
            #Software Update Scan Cycle
                Invoke-WMIMethod -ComputerName $device -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000113}" | Out-Null
            #Software Update Deployment Evaluation Cycle
                Invoke-WMIMethod -ComputerName $device -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000114}" | Out-Null
            #File Collection Cycle
            #   Invoke-WMIMethod -ComputerName $device -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000010}" | Out-Null
            #Hardware Inventory Cycle
                Invoke-WMIMethod -ComputerName $device -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000001}" | Out-Null
            #Software Inventory Cycle
            #   Invoke-WMIMethod -ComputerName $device -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000002}" | Out-Null
            #Software Metering Usage Report Cycle
            #   Invoke-WMIMethod -ComputerName $device -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000031}" | Out-Null
            #State Message Refresh
            #   Invoke-WMIMethod -ComputerName $device -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000111}" | Out-Null
            #User Policy Retrieval Cycle
            #   Invoke-WMIMethod -ComputerName $device -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000026}" | Out-Null
            #User Policy Evaluation Cycle
            #   Invoke-WMIMethod -ComputerName $device -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000027}" | Out-Null
            #Windows Installers Source List Update Cycle
            #   Invoke-WMIMethod -ComputerName $device -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000032}" | Out-Null
            Write-Host -ForegroundColor Green "Actions on $device Complete!"
            }  
            catch {Write-Host -ForegroundColor Red "Error Running actions on $device"}

    #}

}

function Online{
    param ($device)
    
    if ($device -ne $ENV:COMPUTERNAME){
        $NetTest = (Test-NetConnection -hops 2 -ComputerName $device -ErrorAction SilentlyContinue)
            if ($NetTest.PingSucceeded -eq $true){
                Actions -device $device
            }
            else {Write-Host -ForegroundColor Red "Device is not online"}
    }
    else {Actions -device $device}
    
}

function WSUS{
    param ($device)
    Write-Host -ForegroundColor Yellow "Resetting WSUS Compliance State on $device"
    try {
        Invoke-Command -ComputerName $device -ScriptBlock{
            $SCCMUpdatesStore = New-Object -ComObject Microsoft.CCM.UpdatesStore
            $SCCMUpdatesStore.RefreshServerComplianceState()
        }
    }
    catch {Write-Host -ForegroundColor Yellow "Cannot reset WSUS Compliance State on $device"}
}

function clearcache {
    param ($device)
    Write-Host -ForegroundColor Yellow "Clearing cache on $device"
    try {
        Invoke-Command -ComputerName $device -ScriptBlock{
        $resman = new-object -com "UIResource.UIResourceMgr"
        $cacheInfo = $resman.GetCacheInfo()
        $cacheinfo.GetCacheElements()  | foreach {$cacheInfo.DeleteCacheElement($_.CacheElementID)}
        }
        Write-Host -ForegroundColor Green "Cache Cleared on $device!"
    }
    catch {Write-Host -ForegroundColor Red "Error clearing cache on $device"}
    
    
}

function ResetMachinePolicy {
    param ($device)
    Write-Host -ForegroundColor Yellow "Purging machine policy on $device"
    try {
            Invoke-Command -ComputerName $device -ScriptBlock{
            Invoke-WMIMethod -Namespace root\ccm -Class SMS_Client -Name ResetPolicy -ArgumentList “1”
            start-sleep -Seconds 5
            Restart-Service CcmExec -Force | Out-Null
            Start-Sleep -Seconds 60
            Invoke-WMIMethod -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000021}" | Out-Null
        }
        Write-Host -ForegroundColor Red "Successfully purged machine policy on $device"
    }
    catch {Write-Host -ForegroundColor Red "Error purging machine policy on $device"}
}


#if device is specified, runs against that device
if ($device){
    if ($force){Actions -device $device}
    else {Online -device $device}
}

#if neither Device or CollectionID are specified, runs against localhost
if (!($device)-and(!($CollectionID))){
    $device = $ENV:COMPUTERNAME
    $Actions = $true
    if (!($loop)){Actions -device $device}
    if ($loop){
        $n=0
        if ($ResetMachinePolicy -eq $true){
            Actions -device $device
            Write-host -ForegroundColor Red "Disabling machine policy reset during loop"
            $ResetMachinePolicy = $wait
        }
        do {Actions -device $device; Start-Sleep -Seconds 120; $n++}
        until ($n -eq $loop)
        
    }

}



#specifying a Collection ID will connect to sccm, and run actions against a list of collection members
If ($CollectionID){
    $initParams = @{}
    if((Get-Module ConfigurationManager) -eq $null) {
        Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
    }
    if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
        New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
    }
    $strLocation = (Get-Location)
    Set-Location "$($SiteCode):\" @initParams
    $DeviceList = (Get-CMCollectionMember -CollectionId $CollectionID | select-object -ExpandProperty Name)
    $NumDevices = $DeviceList.count
    $CurrentNum = 1
    foreach ($device in $DeviceList){
        Write-Host "$CurrentNum/$NumDevices : $Device"
        $CurrentNum++
        if ($force){
            Actions -device $device
        }
        else {
            Online -device $device
        }
    }
    Set-Location C:
    
}


