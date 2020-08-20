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
#Define locations to cache and upload the installer and scripts
$Script:strTempDirectory = $env:TEMP #inital download directory
$Script:strFinalDirectory = "<srouce share>\<application>\" #final destination for Chrome installers
$Script:strSiteCode = "<SMSSiteCode>" # SCCM Site code 
$Script:strProviderMachineName = "<site server>" # SMS Provider machine name
$Script:strCurrentPkgName = "Google Chrome - Current"
$Script:strPreviousPkgName = "Google Chrome - Rollback"
#Deployment Collections
$Script:strPilotColl = "Deploy | Wkst PILOT | Chrome"
$Script:strWkstAll = "Deploy | Wkst All | Chrome"
$Script:strServerAll = "Deploy | Server | Chrome"
$Script:strCucumberAll = "Deploy | Cucumber | Chrome"
#Query for Outdated versions
$script:strOutdatedChrome = "Query | Google Chrome Outdated"
#defines and resets Chrome version varable
$Script:strChromeVersion = $null

#checking for required external scripts - 
If (!(Test-Path -Path .\Get-MSIFileInformation.ps1)){
    Write-Host "MSI File Information Script not present.  If lost, download from https://www.scconfigmgr.com/2014/08/22/how-to-get-msi-file-information-with-powershell/ " -ForegroundColor Red
    exit
}


#Checking for destination directory
If (!(Test-Path -Path $Script:strFinalDirectory)){
    Write-Host "Unable to locate destination directory, exiting..." -ForegroundColor Red
    exit
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
    $Script:strChromeVersion = (($chromeVersions | Where-Object { $_.os -eq $Platform }).versions | `
            Where-Object { $_.channel -eq $Channel }).current_version
    
    If (!(Test-Path -Path $Script:strFinalDirectory\$strChromeVersion)){
        Write-Host "Chrome $Script:strChromeVersion available, downloading now." -ForegroundColor Yellow
        }
    else {
        Write-Host "Latest Version ($strChromeVersion) already deployed." -ForegroundColor Yellow
        exit
    }
}
Function GetChrome {
    # Download the installer from Google
try {
    $strLinkx64 = 'http://dl.google.com/edgedl/chrome/install/GoogleChromeStandaloneEnterprise64.msi'
	New-Item -ItemType Directory "$strTempDirectory\$strChromeVersion" -Force | Out-Null
    (New-Object System.Net.WebClient).DownloadFile($strLinkx64, "$strTempDirectory\$strChromeVersion\GoogleChromeStandaloneEnterprise64.msi")
    Start-Sleep -Seconds 5
    Write-host "Downloaded Chrome $Script:strChromeVersion" -ForegroundColor Yellow
    } catch {
        Write-Host 'Download failed. There was a problem with the download.' -ForegroundColor Red
        exit
    } 

    #get Product Code for both versions
    Import-Module .\Get-MSIFileInformation.ps1 -Force
    $strProductCodex64 = (MSIInfo -Path "$Script:strTempDirectory\$Script:strChromeVersion\GoogleChromeStandaloneEnterprise64.msi" -Property ProductCode) | Out-String
    $Script:strProductCodex64 = $strProductCodex64.Replace('{','').Replace('}','')

    $strPreviousLocation = (Get-ChildItem -Path $Script:strFinalDirectory -Attributes D | Where-Object { $_.Name -match '\d' } | Sort-Object -Property LastWriteTime | select -last 1).fullname
    $strOldProdcutCode = (MSIInfo -path $strPreviousLocation\GoogleChromeStandaloneEnterprise64.msi -Property ProductCode) | Out-String
    $Script:strOldProductCode = $strOldProdcutCode.Replace('{','').Replace('}','')

    Write-Host "Gathered the following Product Codes." -ForegroundColor Yellow
    Write-Host "New Product Code: "$Script:strProductCodex64 -ForegroundColor Green
    Write-Host "Old Product Code: "$Script:strOldProductCode -ForegroundColor Green
    
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


$installbatch | out-file $strTempDirectory\$strChromeVersion\set-chrome.ps1 -Encoding ascii

Write-Host "Built PoSH installer script" -ForegroundColor Yellow
}

Function UpdateFiles {
    
    try {
        #Create Destination
        #New-Item -ItemType Directory -Path $strFinalDirectory\$strChromeVersion | Out-Null
        # Move the installer to server
        Copy-item -Container -Recurse "$Script:strTempDirectory\$Script:strChromeVersion" $Script:strFinalDirectory
        } catch {
        Write-Host "Upload failed. You will have to move the installer yourself from $Script:strTempDirectory" -ForegroundColor Red
    }
    Write-Host "Uploaded to Source's Share ($Script:strFinalDirectory\$Script:strChromeVersion)" -ForegroundColor Yellow
}


#update deployment package on SCCM to current version, and redistribute
Function SetSCCMDeployment {
Write-Host "Connecting to SCCM Site Server" -ForegroundColor Yellow
#site connection
$initParams = @{}
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}
if((Get-PSDrive -Name $Script:strSiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $Script:strSiteCode -PSProvider CMSite -Root $Script:strProviderMachineName @initParams
}
$curLoc = (Get-Location)
Set-Location "$($Script:strSiteCode):\" @initParams

#Update Collection membership rules for Outdated Chrome
$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_INSTALLED_SOFTWARE on SMS_G_System_INSTALLED_SOFTWARE.ResourceID = SMS_R_System.ResourceId where SMS_G_System_INSTALLED_SOFTWARE.ProductName like 'Google Chrome%' and SMS_G_System_INSTALLED_SOFTWARE.ProductVersion < '$strChromeVersion'"
remove-CMDeviceCollectionQueryMembershipRule -CollectionName $script:strOutdatedChrome -RuleName 'Outdated' -Force
add-CMDeviceCollectionQueryMembershipRule -CollectionName $script:strOutdatedChrome -RuleName "Outdated" -QueryExpression $query


#Build updated Detection Method Clauses
$clause = New-CMDetectionClauseWindowsInstaller -ProductCode $Script:strProductCodex64 -Existence
$PreviousClause = New-CMDetectionClauseWindowsInstaller -ProductCode $Script:strOldProductCode -Existence

#pulling Package information to update
$Script:strCurrentPkg = (Get-CMApplication -Name $strCurrentPkgName)
$strAppMgmt = ([xml]$Script:strCurrentPkg.SDMPackageXML).AppMgmtDigest
$strDeploymentType = $strAppMgmt.DeploymentType | select -First 1
$strPreviousLocation = $strDeploymentType.Installer.Contents.Content.Location

#previous package
$PreviousSDMPackageXML = (Get-CMDeploymentType -ApplicationName "$($Script:strPreviousPkgName)" -DeploymentTypeName "$($Script:strPreviousPkgName)").SDMPackageXML
[string[]]$strPreviousOldDetections = (([regex]'(?<=SettingLogicalName=.)([^"]|\\")*').Matches($PreviousSDMPackageXML)).Value

#current package
$SDMPackageXML = (Get-CMDeploymentType -ApplicationName "$($strCurrentPkgName)" -DeploymentTypeName "$($strCurrentPkgName)").SDMPackageXML
[string[]]$strOldDetections = (([regex]'(?<=SettingLogicalName=.)([^"]|\\")*').Matches($SDMPackageXML)).Value


#paramaters set, populatating chagnes in SCCM now
Write-Host "Updating Deployment Packages" -ForegroundColor Yellow
#previous package
Set-CMApplication -Name $Script:strPreviousPkgName -SoftwareVersion $Script:strCurrentPkg.SoftwareVersion
Set-CMScriptDeploymentType -ApplicationName $Script:strPreviousPkgName -DeploymentTypeName $Script:strPreviousPkgName -ContentLocation $strPreviousLocation -RemoveDetectionClause $strPreviousOldDetections -AddDetectionClause($PreviousClause)
#current package
Set-CMApplication -Name $Script:strCurrentPkgName -SoftwareVersion $Script:strChromeVersion
Set-CMScriptDeploymentType -ApplicationName $Script:strCurrentPkgName -DeploymentTypeName $Script:strCurrentPkgName -ContentLocation $Script:strFinalDirectory\$Script:strChromeVersion -RemoveDetectionClause $strOldDetections -AddDetectionClause($clause)

Write-Host "Redistributing Content" -ForegroundColor Yellow
Update-CMDistributionPoint -ApplicationName $Script:strPreviousPkgName -DeploymentTypeName $Script:strPreviousPkgName
Update-CMDistributionPoint -ApplicationName $Script:strCurrentPkgName -DeploymentTypeName $Script:strCurrentPkgName
#re-schedule deployments
$strServerDate = @(@(0..7) | % {$(Get-Date 18:00:00).AddDays($_)} | ? {$_.DayOfWeek -ieq "Friday"})[0]
Write-Host "Reset deployment deadlines:" -ForegroundColor Yellow
Write-Host "Starting at below times, during maintenance window"  -ForegroundColor Yellow
Set-CMApplicationDeployment -ApplicationName $Script:strCurrentPkgName -CollectionName $Script:strPilotColl -AvailableDateTime (get-date 06:00:00).AddDays(0) -DeadlineDateTime (get-date 18:00:00).AddDays(0)
Write-Host "Pilot : "(get-date 18:00:00).AddDays(0) -ForegroundColor Yellow
Set-CMApplicationDeployment -ApplicationName $Script:strCurrentPkgName -CollectionName $Script:strWkstAll -AvailableDateTime (get-date 06:00:00).AddDays(0)  -DeadlineDateTime (get-date 18:00:00).AddDays(2)
Write-Host "All Wkst : "(get-date 18:00:00).AddDays(2) -ForegroundColor Yellow
Set-CMApplicationDeployment -ApplicationName $Script:strCurrentPkgName -CollectionName $Script:strServerAll -AvailableDateTime (get-date 06:00:00).AddDays(0) -DeadlineDateTime $strServerDate
Write-Host "All Server : "$strServerDate -ForegroundColor Yellow
Set-CMApplicationDeployment -ApplicationName $Script:strCurrentPkgName -CollectionName $Script:strCucumberAll -AvailableDateTime (get-date 06:00:00).AddDays(7) -DeadlineDateTime (get-date 18:00:00).AddDays(14)
Write-Host "Cucumber : "(get-date 18:00:00).AddDays(7) -ForegroundColor Yellow
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
        New-CMApplication -Name $Script:strCurrentPkgName -SoftwareVersion $Script:strChromeVersion
        Add-CMScriptDeploymentType -ApplicationName $Script:strCurrentPkgName -DeploymentTypeName $Script:strCurrentPkgName -ContentLocation $Script:strFinalDirectory\$strChromeVersion -AddDetectionClause($clause) -InstallCommand "set-Chrome.ps1 -Action install" -UninstallCommand "set-Chrome.ps1 -Action uninstall"
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