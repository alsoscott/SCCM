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
if (!(Test-path -path $PSScriptRoot -ErrorAction SilentlyContinue | Out-Null)){
    $ScriptRoot = "C:\Users\Scott\Documents\GitHub\SCCM\ApplicationDeployment"
} else {$ScriptRoot = $PSScriptRoot}

If (!(Test-Path -Path $ScriptRoot\Get-MSIFileInformation.ps1)){
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
Function GetChrome {
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
        $OldProdcutCode = (MSIInfo -path $strPreviousLocation\GoogleChromeStandaloneEnterprise64.msi -Property ProductCode) | Out-String
        $Script:strOldProductCode = $strOldProdcutCode.Replace('{','').Replace('}','')
        Write-Host "Old Product Code: "$Script:OldProductCode -ForegroundColor Green
    }
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
        #Create Destination
        #New-Item -ItemType Directory -Path $strFinalDirectory\$ChromeVersion | Out-Null
        # Move the installer to server
        Copy-item -Container -Recurse "$Script:TempDirectory\$Script:ChromeVersion" $Script:FinalDirectory
        } catch {
        Write-Host "Upload failed. You will have to move the installer yourself from $Script:strTempDirectory" -ForegroundColor Red
    }
    Write-Host "Uploaded to Source's Share ($Script:FinalDirectory\$Script:ChromeVersion)" -ForegroundColor Yellow
}


#update deployment package on SCCM to current version, and redistribute
Function SetSCCMDeployment {
param ([switch]$FirstRun)
Write-Host "Connecting to SCCM Site Server" -ForegroundColor Yellow
$curLoc = (Get-Location)
Set-Location "$($SiteCode):\" @initParams

#Update Collection membership rules for Outdated Chrome
$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_INSTALLED_SOFTWARE on SMS_G_System_INSTALLED_SOFTWARE.ResourceID = SMS_R_System.ResourceId where SMS_G_System_INSTALLED_SOFTWARE.ProductName like 'Google Chrome%' and SMS_G_System_INSTALLED_SOFTWARE.ProductVersion < '$script:ChromeVersion'"
if ($FirstRun){
    if (!(test-path "DeviceCollection\AppQueries")) {Write-Host -ForegroundColor Yellow "Creating AppQueries Folder, Console needs to be restarted if open" ; new-item -Name "AppQueries" -Path $($SiteCode+":\DeviceCollection")}
    if (!(test-path "DeviceCollection\AppDeployments")) {Write-Host -ForegroundColor Yellow "Creating AppDeployments Folder, Console needs to be restarted if open" ; new-item -Name 'AppDeployments' -Path $($SiteCode+":\DeviceCollection")}
    New-CMDeviceCollection -LimitingCollectionName "All Desktop and Server Clients" -Name $Script:QueryOutDateColl
    Add-CMDeviceCollectionQueryMembershipRule -CollectionName $Script:QueryOutDateColl -RuleName "Chrome Outdated" -QueryExpression $query
    New-CMDeviceCollection -LimitingCollectionName "All Desktop and Server Clients" -Name $Script:DeployColl
    Add-CMDeviceCollectionIncludeMembershipRule -CollectionName $Script:DeployColl -IncludeCollectionName $Script:QueryOutDateColl
    Move-CMObject -FolderPath "DeviceCollection\AppQueries" -InputObject (Get-CMDeviceCollection -Name $Script:QueryOutDateColl)
    Move-CMObject -FolderPath "DeviceCollection\AppDeployments" -InputObject (Get-CMDeviceCollection -Name $Script:DeployColl)
} else {
    remove-CMDeviceCollectionQueryMembershipRule -CollectionName $Script:QueryOutDateColl -RuleName 'Outdated' -Force
    add-CMDeviceCollectionQueryMembershipRule -CollectionName $Script:QueryOutDateColl -RuleName "Outdated" -QueryExpression $query
}

#Build updated Detection Method Clauses
$clause = New-CMDetectionClauseWindowsInstaller -ProductCode $Script:ProductCodex64 -Existence
If ($FirstRun){$PreviousClause = New-CMDetectionClauseWindowsInstaller -ProductCode $Script:OldProductCode -Existence}

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
    New-CMApplication -Name $Script:CurrentPkgName -AutoInstall $true -Description $Script:CurrentPkgName -SoftwareVersion $Script:ChromeVersion
    Add-CMScriptDeploymentType -ApplicationName $Script:CurrentPkgName -DeploymentTypeName $Script:CurrentPkgName -ContentLocation $Script:FinalDirectory\$Script:ChromeVersion -InstallCommand "set-chrome.ps1 -Action Install" -InstallationBehaviorType InstallForSystem -AddDetectionClause $clause1
    Start-CMContentDistribution -ApplicationName $Script:CurrentPkgName -DistributionPointGroupName $((Get-CMDistributionPointGroup).Name)
    #rollback applications
    New-CMApplication -Name $Script:PreviousPkgName -AutoInstall $true -Description $Script:PreviousPkgName -SoftwareVersion $Script:ChromeVersion
    Add-CMScriptDeploymentType -ApplicationName $Script:PreviousPkgName -DeploymentTypeName $Script:PreviousPkgName -ContentLocation $Script:FinalDirectory\$Script:ChromeVersion -InstallCommand "set-chrome.ps1 -Action Rollback" -InstallationBehaviorType InstallForSystem -AddDetectionClause $clause1 -
    Start-CMContentDistribution -ApplicationName $Script:CurrentPkgName -DistributionPointGroupName $((Get-CMDistributionPointGroup).Name)

    New-CMApplicationDeployment -CollectionName $Script:DeployColl -ApplicationName $Script:CurrentPkgName -DeployAction Install -DeployPurpose Required -UserNotification DisplaySoftwareCenterOnly -AvailableDateTime (get-date 06:00:00).AddDays(0) -DeadlineDateTime (get-date 18:00:00).AddDays(1) -TimeBaseOn LocalTime
    New-CMApplicationDeployment -CollectionName $Script:QueryOutDateColl -ApplicationName $Script:CurrentPkgName -DeployAction Install -DeployPurpose Required -UserNotification DisplaySoftwareCenterOnly -AvailableDateTime (get-date 06:00:00).AddDays(0) -DeadlineDateTime (get-date 18:00:00).AddDays(7) -TimeBaseOn LocalTime
} else {
    Write-Host "Updating Deployment Packages" -ForegroundColor Yellow
    #previous package
    Set-CMApplication -Name $Script:PreviousPkgName -SoftwareVersion $Script:CurrentPkg.SoftwareVersion
    Set-CMScriptDeploymentType -ApplicationName $Script:PreviousPkgName -DeploymentTypeName $Script:PreviousPkgName -ContentLocation $PreviousLocation -RemoveDetectionClause $PreviousOldDetections -AddDetectionClause($PreviousClause)
    #current package
    Set-CMApplication -Name $Script:CurrentPkgName -SoftwareVersion $Script:ChromeVersion
    Set-CMScriptDeploymentType -ApplicationName $Script:CurrentPkgName -DeploymentTypeName $Script:CurrentPkgName -ContentLocation $Script:FinalDirectory\$Script:ChromeVersion -RemoveDetectionClause $OldDetections -AddDetectionClause($clause)
    Write-Host "Redistributing Content" -ForegroundColor Yellow
    Update-CMDistributionPoint -ApplicationName $Script:PreviousPkgName -DeploymentTypeName $Script:PreviousPkgName
    Update-CMDistributionPoint -ApplicationName $Script:CurrentPkgName -DeploymentTypeName $Script:CurrentPkgName    
} 

#re-schedule deployments
$strServerDate = @(@(0..7) | % {$(Get-Date 18:00:00).AddDays($_)} | ? {$_.DayOfWeek -ieq "Friday"})[0]
Write-Host "Reset deployment deadlines:" -ForegroundColor Yellow
Write-Host "Starting at below times, during maintenance window"  -ForegroundColor Yellow
Set-CMApplicationDeployment -ApplicationName $Script:strCurrentPkgName -CollectionName $Script:strPilotColl -AvailableDateTime (get-date 06:00:00).AddDays(0) -DeadlineDateTime (get-date 18:00:00).AddDays(0)

<# ---- Pilot, All deployments
Write-Host "Pilot : "(get-date 18:00:00).AddDays(0) -ForegroundColor Yellow
Set-CMApplicationDeployment -ApplicationName $Script:strCurrentPkgName -CollectionName $Script:strWkstAll -AvailableDateTime (get-date 06:00:00).AddDays(0)  -DeadlineDateTime (get-date 18:00:00).AddDays(2)
Write-Host "All Wkst : "(get-date 18:00:00).AddDays(2) -ForegroundColor Yellow
Set-CMApplicationDeployment -ApplicationName $Script:strCurrentPkgName -CollectionName $Script:strServerAll -AvailableDateTime (get-date 06:00:00).AddDays(0) -DeadlineDateTime $strServerDate
#>
#return to local disk
Set-Location $curLoc
}

Function FirstRun {
Write-Host "Creating Application and Deployment Package." -ForegroundColor Yellow
Write-Host "Connecting to SCCM Site Server" -ForegroundColor Yellow
#site connection
$initParams = @{}
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
    }
    if((Get-PSDrive -Name $Script:strSiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
        New-PSDrive -Name $Script:strSiteCode -PSProvider CMSite -Root $Script:strProviderMachineName @initParams
        }
    Set-Location "$($strSiteCode):\" @initParams
            
    #Build updated Detection Method Clauses
        $clause = New-CMDetectionClauseWindowsInstaller -ProductCode $Script:strProductCodex64 -Existence
        $clause.Connector = 'Or'
    #paramaters set, populatating changes in SCCM now
        Write-Host "Creating Deployment Packages" -ForegroundColor Yellow
        New-CMApplication -Name $Script:strCurrentPkgName -SoftwareVersion $Script:ChromeVersion
        Add-CMScriptDeploymentType -ApplicationName $Script:strCurrentPkgName -DeploymentTypeName $Script:strCurrentPkgName -ContentLocation $Script:FinalDirectory\$ChromeVersion -AddDetectionClause($clause) -InstallCommand "set-Chrome.ps1 -Action install" -UninstallCommand "set-Chrome.ps1 -Action uninstall"
        Write-Host "Distributing Content" -ForegroundColor Yellow
        Update-CMDistributionPoint -ApplicationName $Script:strPreviousPkgName -DeploymentTypeName $Script:strPreviousPkgName
        Update-CMDistributionPoint -ApplicationName $Script:strCurrentPkgName -DeploymentTypeName $Script:strCurrentPkgName
    #return to local disk
        sl c:
        
}




Get-ChromeVersion
GetChrome
CreateBatch
UpdateFiles
If ($FirstRun){
   FirstRun
}
Else {
    SetSCCMDeployment
} 
Clear-Variable -Name "str*"
Write-Host "Complete!" -ForegroundColor Yellow