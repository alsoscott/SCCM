<#
************************************************************************************************************************
.SYNOPSIS
    Run actions and/or clear cache against localhost, individual remote device, or SCCM collection of devices.
 
    Disclaimer: This script is provided "AS IS" with no warranties, confers no rights and is not supported by the author.
    Author - Scott Churchill
    Contact - Various places on internet as AlsoScott

.DESCRIPTION
    This is a Powershell script to run actions and/or clear cache against localhost, individual remote device, or collection of devices.


.EXAMPLE
    Localhost
./SCCM_Client_Actions.ps1 (runs client actions against localhost)
./SCCM_Client_Actions.ps1 -ClearCache (runs client actions and clears SCCM Cache against localhost)


.EXAMPLE
    Individual Remote Device
./SCCM_Client_Actions.ps1 -device <device name> (runs client actions against <remote device>)
./SCCM_Client_Actions.ps1 -device <device name> -ClearCache (clears cache and runs actions against <remote device>)
./SCCM_Client_Actions.ps1 -force -device <device name> (bypasses online check for remote device)

.EXAMPLE
    SCCM Collections
./SCCM_Client_Actions.ps1 -CollectionID <collection ID> (runs actions against SCCM <collection ID>)
./SCCM_Client_Actions.ps1 -CollectionID <Collection ID> -ClearCache (clears cache and Runs actions against SCCM <Collection ID>)
./SCCM_Client_Actions.ps1 -CollectionID <Collection ID> -ClearCache -force (bypasses online check, clears cache and runs actions against SCCM <Collection ID>)


.NOTES
    Created:    June 1st 2019
    Version:    1.1

Update: 21 June 2019
    Added Force param to bypass online checkes (some devices are online, but ICMP is blocked by network config)
    Added Clear Cache function
    
Update: 1 June 2019
    Creatied initial script - took initial client actions script, added remote functionality, added SCCM Collection polling
************************************************************************************************************************
#>

#parameters, none are required.
param($device,$CollectionID,[switch]$ClearCache,[switch]$Force)
# SCCM Site configuration
$SiteCode = "" # Site code 
$ProviderMachineName = "" # SMS Provider machine name

function Actions{
    param ($device)
    if ($ClearCache){clearcache -device $device}
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
    #   Invoke-WMIMethod -ComputerName $device -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule "{00000000-0000-0000-0000-000000000001}" | Out-Null
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
}

function Online{
    param ($device)
    
    if ($device -ne $ENV:COMPUTERNAME){
        $NetTest = (Test-NetConnection -ComputerName $device -ErrorAction SilentlyContinue)
            if ($NetTest.PingSucceeded -eq $true){
                Actions -device $device
            }
            else {Write-Host -ForegroundColor Red "Device is not online"}
    }
    else {Actions -device $device}
    
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

#if device is specified, runs against that device
if ($device){
    if ($force){
        Actions -device $device
    }
    else {
        Online -device $device
    }
}

#if neither Device or CollectionID are specified, runs against localhost
if (!($device)-and(!($CollectionID))){
    $device = $ENV:COMPUTERNAME
    Actions -device $device

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


