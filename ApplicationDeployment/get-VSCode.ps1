<#
 ************************************************************************************************************************
Created:    2019-05-27
Version:    1.2

#Update: 2 July 2020
Copied from updated script and sanitized for public use
 
Disclaimer:
This script is provided "AS IS" with no warranties, confers no rights and 
is not supported by the author.
 
Author - Scott Churchill
Contact - Various places on internet as AlsoScott

Notes - before running script for first time, set base paramaters including Sources share, Site code, Site Server
After base paramaters are set, you can use the FirstRun switch to build out required collections
Required additional script needed: Get-MSIFileInformation.ps1 which can be obtained from:
    https://www.scconfigmgr.com/2014/08/22/how-to-get-msi-file-information-with-powershell/ 

************************************************************************************************************************
#>
param ([switch]$FirstRun)
$TempDirectory = $env:TEMP #inital download directory
$Script:FinalDirectory = "\\server\share" #final destination for VSCode installers
$SiteCode = "SMSSiteCode" # SCCM Site code 
$ProviderMachineName = "SCCM Site Server" # SMS Provider machine name
$Script:CurrentPkgName = "VSCode - Current"
$Script:strDeployColl = "Deploy | VSCode"
#Checking for destination directory
If (!(Test-Path -Path $Script:FinalDirectory)){
    Write-Host "Unable to locate destination directory, exiting..." -ForegroundColor Red
    exit
}

Function GetVersion {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ie = New-Object -com internetexplorer.application
    $url = "https://code.visualstudio.com/updates"
    $ie.navigate($url)
    while ($ie.Busy -eq $true) { Start-Sleep -Seconds 5}
    $titles = $ie.Document.body.getElementsByTagName('H1')
    foreach ($storyTitle in $titles) {
         $VSCodeVersion = $storyTitle.innerText | Select-String "\d\.\d\d" -AllMatches |
         foreach {$_.Matches} | foreach {$_.Value}         
    }
    If (!($VSCodeVersion)){Write-Host "Version not found." -ForegroundColor Yellow; exit 1}
        If (!(Test-Path -Path $Script:FinalDirectory\$VSCodeVersion)){
        Write-Host "New Version Needed, VSCode $VSCodeVersion downloading now." -ForegroundColor Yellow
    }
    else {
        Write-Host "Latest Version ($VSCodeVersion) already deployed." -ForegroundColor Yellow
        exit
    }
}
Function GetVSCode {
    # Download the installer
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ie = New-Object -com internetexplorer.application
    $url = "https://update.code.visualstudio.com/$VSCodeVersion.0/win32-x64/stable"
    #$Filex64 = "VSCode.$VSCodeVersion.exe"
    #$ie.navigate($url)
    #$Linkx64 = "$url/$Filex64"
    
    New-Item -ItemType Directory "$TempDirectory\$VSCodeVersion" -Force | Out-Null
    (New-Object System.Net.WebClient).DownloadFile($url, "$TempDirectory\$VSCodeVersion\VSCode64.exe")
    Start-Sleep -Seconds 15
    Write-host "Files Downloaded to $TempDirectory\$VSCodeVersion" -ForegroundColor Yellow
    } 
    catch {Write-Host 'Download failed. There was a problem with the download.' -ForegroundColor Red; exit} 
}
Function UpdateFiles {
    Write-Host "Uploading to Source's Share ($Script:FinalDirectory\$VSCodeVersion)" -ForegroundColor Yellow
    try {
        # Copy the installer to server
        Copy-item -Container -Recurse "$TempDirectory\$VSCodeVersion" $Script:FinalDirectory
        Copy-item  "$Script:FinalDirectory\set-VSCode.ps1" $Script:FinalDirectory\$VSCodeVersion
        } catch {
        Write-Host "Upload failed. You will have to move the installer yourself from $TempDirectory" -ForegroundColor Red
    }
}

#update deployment package on SCCM to current version, and redistribute
Function SetSCCMDeployment {
Write-Host "Connecting to SCCM Site Server" -ForegroundColor Yellow
#site connection
$initParams = @{}
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}
Set-Location "$($SiteCode):\" @initParams
    
#Build updated Detection Method Clauses
$clause = New-CMDetectionClauseFile -Value -Path "%ProgramFiles%\Microsoft VS Code" -FileName "Code.exe" -PropertyType Version -ExpressionOperator GreaterEquals -ExpectedValue $VSCodeVersion
#pulling Package information to update
$SDMPackageXML = (Get-CMDeploymentType -ApplicationName "$($Script:CurrentPkgName)" -DeploymentTypeName "$($Script:CurrentPkgName)").SDMPackageXML
[string[]]$OldDetections = (([regex]'(?<=SettingLogicalName=.)([^"]|\\")*').Matches($SDMPackageXML)).Value
#paramaters set, populatating chagnes in SCCM now
Write-Host "Updating Deployment Packages" -ForegroundColor Yellow
Set-CMApplication -Name $Script:CurrentPkgName -SoftwareVersion $VSCodeVersion
Set-CMScriptDeploymentType -ApplicationName $Script:CurrentPkgName -DeploymentTypeName $Script:CurrentPkgName -ContentLocation $Script:FinalDirectory\$VSCodeVersion -RemoveDetectionClause $OldDetections -AddDetectionClause($clause)
Write-Host "Redistributing Content" -ForegroundColor Yellow
update-CMDistributionPoint -ApplicationName $Script:CurrentPkgName -DeploymentTypeName $Script:CurrentPkgName 
#re-schedule deployments
Set-CMApplicationDeployment -ApplicationName $Script:CurrentPkgName -CollectionName $Script:strDeployColl -AvailableDateTime (get-date 06:00:00).AddDays(0) -DeadlineDateTime (get-date 18:00:00).AddDays(1)
#return to local disk
sl c:
}

Function FirstRun {
    Write-Host "Creating Application and Deployment Package." -ForegroundColor Yellow
    Write-Host "Connecting to SCCM Site Server" -ForegroundColor Yellow
#site connection
$initParams = @{}
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
    }
    if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
        New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
        }
    Set-Location "$($SiteCode):\" @initParams
        #Build Deployment collection
        New-CMDeviceCollection -LimitingCollectionName "All Desktop and Server Clients" -Name $Script:strDeployColl -RefreshType Periodic
        #Build updated Detection Method Clauses
        $clause1 = New-CMDetectionClauseFile -Value -Path "%ProgramFiles%\Microsoft VS Code" -FileName "Code.exe" -PropertyType Version -ExpressionOperator GreaterEquals -ExpectedValue $VSCodeVersion
        #paramaters set, populatating chagnes in SCCM now
        Write-Host "Creating Deployment Packages" -ForegroundColor Yellow
        New-CMApplication -Name $Script:CurrentPkgName -SoftwareVersion $VSCodeVersion
        Add-CMScriptDeploymentType -ApplicationName $Script:CurrentPkgName -DeploymentTypeName $Script:CurrentPkgName -ContentLocation $Script:FinalDirectory\$VSCodeVersion -AddDetectionClause($clause1) -InstallCommand "'set-VSCode.ps1' -Perform Install" -UninstallCommand "'set-VSCode.ps1' -Perform Uninstall"
        #Distributing content
        Write-Host "Distributing Content" -ForegroundColor Yellow
        Start-CMContentDistribution -ApplicationName $Script:CurrentPkgName -DistributionPointName $ProviderMachineName
        #Create Deployment
        New-CMApplicationDeployment -Name $Script:CurrentPkgName -CollectionName $Script:strDeployColl -DeployAction Install -DeployPurpose Required -UserNotification DisplaySoftwareCenterOnly -TimeBaseOn LocalTime -AvailableDateTime (get-date 06:00:00).AddDays(0) -DeadlineDateTime (get-date 18:00:00).AddDays(1)
        #return to local disk
        sl c:
        
}

GetVersion
GetVSCode
UpdateFiles
If ($FirstRun){
   FirstRun
}
Else {
    SetSCCMDeployment
} 
Write-Host "Complete!" -ForegroundColor Yellow