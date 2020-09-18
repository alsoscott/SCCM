<#
 ************************************************************************************************************************
Created:    2019-05-27
Version:    1.2

#Update: 12 June 2019

 
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
 
if (!(get-psdrive -PSProvider CMSite -ErrorAction SilentlyContinue)) {. ..\set-sccmsite.ps1}
$Script:TempDirectory = $env:TEMP #inital download directory
#package names
$Script:CurrentPkgName = "Google Chrome"
$Script:PreviousPkgName = "Google Chrome (Rollback)"
#deployment collections
$Script:DeployColl = "Deploy | Google Chrome"
$Script:DeployRollbackColl = "Deploy | Google Chrome (Rollback)"
$Script:QueryOutDateColl = "Query | Google Chrome Outdated"

#reset ChromeVersion
$Script:ChromeVersion = $null
#sets source share
$SourceShare = "\\$ProviderMachineName\Source$"
$Script:FinalDirectory = "$SourceShare\Software\Chrome"

#Checking for destination directory
If (!(Test-Path -Path $Script:FinalDirectory)){
    Write-Host "Unable to locate destination directory, attempting to create..." -ForegroundColor Yellow
    try {new-item -ItemType Directory -Path $Script:FinalDirectory | Out-Null; Write-Host -ForegroundColor Green "Success!"}
    catch {Write-Host -ForegroundColor Red "Unable to create $Script:FinalDirectory - must exit now"; exit 0}
}


#checking for required external scripts
If (!(Test-Path -Path $PSScriptRoot\Get-MSIFileInformation.ps1)){
    Write-Host "MSI File Information Script not present.  If lost, download from https://www.scconfigmgr.com/2014/08/22/how-to-get-msi-file-information-with-powershell/ " -ForegroundColor Red
    exit
}


#Checking for destination directory
If (!(Test-Path -Path $Script:FinalDirectory)){
    Write-Host "Unable to locate destination directory, attempting to create..." -ForegroundColor Yellow
    try {new-item -ItemType Directory -Path $Script:FinalDirectory | Out-Null; Write-Host -ForegroundColor Green "Success!"}
    catch {Write-Host -ForegroundColor Red "Unable to create $Script:FinalDirectory - must exit now"; exit 0}
}

Function Get-ChromeVersion {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $False)]
        [string] $Uri = "https://omahaproxy.appspot.com/all.json",
 
        [Parameter(Mandatory = $False)]
        [ValidateSet('win', 'win64', 'mac', 'linux', 'ios', 'cros', 'android', 'webview')]
        [string] $Platform = "win",
 
        [Parameter(Mandatory = $False)]
        [ValidateSet('stable', 'beta', 'dev', 'canary', 'canary_asan')]
        [string] $Channel = "stable"
    )
 
    # Read the JSON and convert to a PowerShell object. Return the current release version of Chrome
    $chromeVersions = (Invoke-WebRequest -uri $Uri).Content | ConvertFrom-Json
    $Script:ChromeVersion = (($chromeVersions | Where-Object { $_.os -eq $Platform }).versions | `
            Where-Object { $_.channel -eq $Channel }).current_version
    
    If (!(Test-Path -Path $Script:FinalDirectory\$Script:ChromeVersion)){
        Write-Host "Chrome $Script:ChromeVersion available, downloading now." -ForegroundColor Yellow
        }
    else {
        Write-Host "Latest Version ($Script:ChromeVersion) already deployed." -ForegroundColor Yellow
        exit
    }
}
Function Download-Chrome {
    param ([switch]$FirstRun)
    # Download the installer from Google
try {
    $Linkx64 = 'http://dl.google.com/edgedl/chrome/install/GoogleChromeStandaloneEnterprise64.msi'
	New-Item -ItemType Directory "$Script:TempDirectory\$script:ChromeVersion" -Force | Out-Null
    (New-Object System.Net.WebClient).DownloadFile($Linkx64, "$Script:TempDirectory\$script:ChromeVersion\GoogleChromeStandaloneEnterprise64.msi")
    Start-Sleep -Seconds 5
    Write-host "Downloaded Chrome $Script:ChromeVersion" -ForegroundColor Yellow
    } catch {
        Write-Host 'Download failed. There was a problem with the download.' -ForegroundColor Red
        exit
    } 
    #get Product Code for both versions
    Import-Module .\Get-MSIFileInformation.ps1 -Force
    $ProductCodex64 = (MSIInfo -Path "$Script:TempDirectory\$Script:ChromeVersion\GoogleChromeStandaloneEnterprise64.msi" -Property ProductCode) | Out-String
    $Script:ProductCodex64 = $ProductCodex64.Replace('{','').Replace('}','')
    Write-Host "Gathered the following Product Codes." -ForegroundColor Yellow
    Write-Host "New Product Code: "$Script:ProductCodex64 -ForegroundColor Green

    if (!($FirstRun)){
        $PreviousLocation = (Get-ChildItem -Path $Script:FinalDirectory -Attributes D | Where-Object { $_.Name -match '\d' } | Sort-Object -Property LastWriteTime | select -last 1).fullname
        $OldProdcutCode = (MSIInfo -path $PreviousLocation\GoogleChromeStandaloneEnterprise64.msi -Property ProductCode) | Out-String
        $Script:OldProductCode = $OldProdcutCode.Replace('{','').Replace('}','')
        Write-Host "Old Product Code: "$Script:OldProductCode -ForegroundColor Green
    } else {$Script:OldProductCode = $Script:ProductCodex64}
}

Function CreateBatch {
#create installer/removal scipts
$installbatch=@'
param ([parameter(Mandatory=$true)][string]$Action)
if (!($PSScriptRoot)){$PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path}
if (!($PSScriptRoot)){exit 1}

if ($action -eq "rollback"){
    if (get-process Chrome -ErrorAction SilentlyContinue) {get-process Chrome | stop-process -force}
    $UninstallCode = (Get-WmiObject -Class SMS_InstalledSoftware -Namespace root\cimv2\sms -Filter "ProductName = 'Google Chrome'").SoftwareCode
    msiexec.exe /X $UninstallCode /qn
    do {start-sleep -Seconds 5} until (!(test-path 'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'))
    msiexec /i GoogleChromeStandaloneEnterprise64.msi /qn /norestart REINSTALLMODE=vomus
    do {start-sleep -Seconds 5} until (test-path 'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe')
}

if ($action -eq "install"){
    if (get-process Chrome -ErrorAction SilentlyContinue) {get-process Chrome | stop-process -force}
    msiexec /i GoogleChromeStandaloneEnterprise64.msi /qn /norestart REINSTALLMODE=vomus
	do {start-sleep -Seconds 5} until (test-path 'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe')
    }

if ($action -eq "uninstall"){
    if (get-process Chrome -ErrorAction SilentlyContinue) {get-process Chrome | stop-process -force}
    $UninstallCode = (Get-WmiObject -Class SMS_InstalledSoftware -Namespace root\cimv2\sms -Filter "ProductName = 'Google Chrome'").SoftwareCode
    msiexec.exe /X $UninstallCode /qn
    do {start-sleep -Seconds 5} until (!(test-path 'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'))
}
'@


$installbatch | out-file $Script:TempDirectory\$ChromeVersion\set-chrome.ps1 -Encoding ascii

Write-Host "Built PoSH installer script" -ForegroundColor Yellow
}

Function UpdateFiles {
    
    try {
        Copy-item -Container -Recurse -Force "$Script:TempDirectory\$Script:ChromeVersion" $Script:FinalDirectory
        } catch {
        Write-Host "Upload failed. You will have to move the installer yourself from $Script:strTempDirectory" -ForegroundColor Red
    }
    Write-Host "Uploaded to Source's Share ($Script:FinalDirectory\$Script:ChromeVersion)" -ForegroundColor Yellow
}


#update deployment package on SCCM to current version, and redistribute
Function Set-SCCMDeployment {
param ([switch]$FirstRun)
Write-Host "Connecting to SCCM Site Server" -ForegroundColor Yellow
$curLoc = (Get-Location)
Set-Location "$($SiteCode):\" @initParams

#Update Collection membership rules for Outdated Chrome
$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_INSTALLED_SOFTWARE on SMS_G_System_INSTALLED_SOFTWARE.ResourceID = SMS_R_System.ResourceId where SMS_G_System_INSTALLED_SOFTWARE.ProductName like 'Google Chrome%' and SMS_G_System_INSTALLED_SOFTWARE.ProductVersion < '$script:ChromeVersion'"
if ($FirstRun){
    if (!(test-path "DeviceCollection\AppQueries")) {Write-Host -ForegroundColor Yellow "Creating AppQueries Folder, Console needs to be restarted if open" ; new-item -Name "AppQueries" -Path $($SiteCode+":\DeviceCollection")}
    if (!(test-path "DeviceCollection\AppDeployments")) {Write-Host -ForegroundColor Yellow "Creating AppDeployments Folder, Console needs to be restarted if open" ; new-item -Name 'AppDeployments' -Path $($SiteCode+":\DeviceCollection")}
    #Create Outdated Collection - Query for Chrome with outdated versions
    New-CMDeviceCollection -LimitingCollectionName "All Desktop and Server Clients" -Name $Script:QueryOutDateColl
    Add-CMDeviceCollectionQueryMembershipRule -CollectionName $Script:QueryOutDateColl -RuleName "Chrome Outdated" -QueryExpression $query
    #Create Deployment Collection - Includes Outdated Query Collection
    New-CMDeviceCollection -LimitingCollectionName "All Desktop and Server Clients" -Name $Script:DeployColl
    Add-CMDeviceCollectionIncludeMembershipRule -CollectionName $Script:DeployColl -IncludeCollectionName $Script:QueryOutDateColl
    #Create Rollback Deployment Collection - this has no membership rules
    New-CMDeviceCollection -LimitingCollectionName "All Desktop and Server Clients" -Name $Script:DeployRollbackColl
    #move above collections into folders
    Move-CMObject -FolderPath "DeviceCollection\AppQueries" -InputObject (Get-CMDeviceCollection -Name $Script:QueryOutDateColl)
    Move-CMObject -FolderPath "DeviceCollection\AppDeployments" -InputObject (Get-CMDeviceCollection -Name $Script:DeployColl)
    Move-CMObject -FolderPath "DeviceCollection\AppDeployments" -InputObject (Get-CMDeviceCollection -Name $Script:DeployRollbackColl)
} else {
    remove-CMDeviceCollectionQueryMembershipRule -CollectionName $Script:QueryOutDateColl -RuleName 'Outdated' -Force
    add-CMDeviceCollectionQueryMembershipRule -CollectionName $Script:QueryOutDateColl -RuleName "Outdated" -QueryExpression $query
}

#Build updated Detection Method Clauses
$clause = New-CMDetectionClauseWindowsInstaller -ProductCode $Script:ProductCodex64 -Existence
If ($FirstRun){$PreviousClause = New-CMDetectionClauseWindowsInstaller -ProductCode $Script:ProductCodex64 -Existence} else {
    $PreviousClause = New-CMDetectionClauseWindowsInstaller -ProductCode $Script:OldProductCode -Existence
}

#pulling Package information to update
if (!($FirstRun)) {
    $CurrentPkg = (Get-CMApplication -Name $Script:CurrentPkgName)
    $AppMgmt = ([xml]$CurrentPkg.SDMPackageXML).AppMgmtDigest
    $DeploymentType = $AppMgmt.DeploymentType | select -First 1
    $PreviousLocation = $DeploymentType.Installer.Contents.Content.Location
    #previous package
    $PreviousSDMPackageXML = (Get-CMDeploymentType -ApplicationName "$($Script:PreviousPkgName)" -DeploymentTypeName "$($Script:PreviousPkgName)").SDMPackageXML
    [string[]]$PreviousOldDetections = (([regex]'(?<=SettingLogicalName=.)([^"]|\\")*').Matches($PreviousSDMPackageXML)).Value
    #current package
    $SDMPackageXML = (Get-CMDeploymentType -ApplicationName "$($CurrentPkgName)" -DeploymentTypeName "$($CurrentPkgName)").SDMPackageXML
    [string[]]$OldDetections = (([regex]'(?<=SettingLogicalName=.)([^"]|\\")*').Matches($SDMPackageXML)).Value
}

#paramaters set, populatating chagnes in SCCM now
if ($FirstRun){
    Write-Host "Creating Application, Deployment Type and deploying to $Script:DeployColl" -ForegroundColor Yellow  
    #Create Current Application
    Write-host "Creating Applicaton, Deployment Type, and Deplying to $Script:DeployColl"
    New-CMApplication -Name $Script:CurrentPkgName -AutoInstall $true -Description $Script:CurrentPkgName -SoftwareVersion $Script:ChromeVersion
    Add-CMScriptDeploymentType -ApplicationName $Script:CurrentPkgName -DeploymentTypeName $Script:CurrentPkgName -ContentLocation $Script:FinalDirectory\$Script:ChromeVersion -InstallCommand "set-chrome.ps1 -Action Install" -InstallationBehaviorType InstallForSystem -AddDetectionClause $clause
    Write-Host "Distributing $Script:CurrentPkgName" -ForegroundColor Yellow
    Start-CMContentDistribution -ApplicationName $Script:CurrentPkgName -DistributionPointGroupName $((Get-CMDistributionPointGroup).Name)
    New-CMApplicationDeployment -CollectionName $Script:DeployColl -ApplicationName $Script:CurrentPkgName -DeployAction Install -DeployPurpose Required -UserNotification DisplaySoftwareCenterOnly -AvailableDateTime (get-date 06:00:00).AddDays(0) -DeadlineDateTime (get-date 18:00:00).AddDays(1) -TimeBaseOn LocalTime
    #Create Rollback Applications
    Write-host "Creating Rollback Applicaton, Deployment Type, and Deplying to $Script:DeployRollbackColl"
    New-CMApplication -Name $Script:PreviousPkgName -AutoInstall $true -Description $Script:PreviousPkgName -SoftwareVersion $Script:ChromeVersion
    Add-CMScriptDeploymentType -ApplicationName $Script:PreviousPkgName -DeploymentTypeName $Script:PreviousPkgName -ContentLocation $Script:FinalDirectory\$Script:ChromeVersion -InstallCommand "set-chrome.ps1 -Action Rollback" -InstallationBehaviorType InstallForSystem -AddDetectionClause $clause
    Write-Host "Distributing $Script:PreviousPkgName" -ForegroundColor Yellow
    Start-CMContentDistribution -ApplicationName $Script:PreviousPkgName -DistributionPointGroupName $((Get-CMDistributionPointGroup).Name)
    New-CMApplicationDeployment -CollectionName $Script:DeployRollbackColl -ApplicationName $Script:PreviousPkgName -DeployAction Install -DeployPurpose Available -UserNotification DisplaySoftwareCenterOnly -AvailableDateTime (get-date 06:00:00).AddDays(0) -TimeBaseOn LocalTime
} else {
    Write-Host "Updating Existing Deployment Packages" -ForegroundColor Yellow
    #previous package
    Set-CMApplication -Name $Script:PreviousPkgName -SoftwareVersion $Script:CurrentPkg.SoftwareVersion
    Set-CMScriptDeploymentType -ApplicationName $Script:PreviousPkgName -DeploymentTypeName $Script:PreviousPkgName -ContentLocation $PreviousLocation -RemoveDetectionClause $PreviousOldDetections -AddDetectionClause($PreviousClause)
    Write-Host "Reset deployment deadlines:" -ForegroundColor Yellow
    Set-CMApplicationDeployment -ApplicationName $Script:PreviousPkgName -CollectionName $Script:DeployRollbackColl -AvailableDateTime (get-date 06:00:00).AddDays(0)
    #current package
    Set-CMApplication -Name $Script:CurrentPkgName -SoftwareVersion $Script:ChromeVersion
    Set-CMScriptDeploymentType -ApplicationName $Script:CurrentPkgName -DeploymentTypeName $Script:CurrentPkgName -ContentLocation $Script:FinalDirectory\$Script:ChromeVersion -RemoveDetectionClause $OldDetections -AddDetectionClause($clause)
    Write-Host "Reset deployment deadlines:" -ForegroundColor Yellow
    Set-CMApplicationDeployment -ApplicationName $Script:PreviousPkgName -CollectionName $Script:DeployRollbackColl -AvailableDateTime (get-date 06:00:00).AddDays(0) -DeadlineDateTime (get-date 18:00:00).AddDays(1) 
    Write-Host "Redistributing Content for $Script:CurrentPkgName and $Script:PreviousPkgName " -ForegroundColor Yellow
    Update-CMDistributionPoint -ApplicationName $Script:PreviousPkgName -DeploymentTypeName $Script:PreviousPkgName
    Update-CMDistributionPoint -ApplicationName $Script:CurrentPkgName -DeploymentTypeName $Script:CurrentPkgName    
} 

#return to local disk
Set-Location $curLoc
}


Get-ChromeVersion
if ($FirstRun){download-Chrome -FirstRun} else {download-Chrome}
CreateBatch
UpdateFiles
If ($FirstRun){Set-SCCMDeployment -FirstRun} Else {Set-SCCMDeployment} 
Write-Host "Complete!" -ForegroundColor Yellow