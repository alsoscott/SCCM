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
#Define locations to cache and upload the installer and scripts
$Script:strTempDirectory = $env:TEMP #inital download directory
$Script:strFinalDirectory = "\\server\share" #final destination for Chrome installers
$Script:strSiteCode = "SMSSiteCode" # SCCM Site code 
$Script:strProviderMachineName = "SCCM Site Server" # SMS Provider machine name
$Script:strCurrentPkgName = "Google Chrome - Current"
$Script:strPreviousPkgName = "Google Chrome - Previous"
#Deployment Collections
$Script:strPilotColl = "CollectionName"
$Script:strWkstAll = "CollectionName"
$Script:strServerAll = "CollectionName"
$Script:strOutdatedColl = "CollectionName"
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

Function GetVersion {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ie = New-Object -com internetexplorer.application
    $url = "https://cloud.google.com/chrome-enterprise/browser/download/"
    $ie.navigate($url)
    while ($ie.Busy -eq $true) { Start-Sleep -Seconds 5; }
    $titles = $ie.Document.body.getElementsByClassName('cloud-browser-downloads__dl-row-chrome-version') | select -First 1
    foreach ($storyTitle in $titles) {
         $strChromeVersion = $storyTitle.innerText
         }
    Set-Variable -Name strChromeVersion -Value ($strChromeVersion) -Scope Script
    #$Script:strChromeVersion = $strChromeVersion
    If (!($Script:strChromeVersion)){Write-Output "Chrome Version undetected, exiting"; exit}
    #kills ie after running
    $ie.Quit()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($ie) | Out-Null
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()

    
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
	$strLinkx86 = 'http://dl.google.com/edgedl/chrome/install/GoogleChromeStandaloneEnterprise.msi'
    New-Item -ItemType Directory "$strTempDirectory\$strChromeVersion" -Force | Out-Null
    (New-Object System.Net.WebClient).DownloadFile($strLinkx64, "$strTempDirectory\$strChromeVersion\GoogleChromeStandaloneEnterprise64.msi")
    (New-Object System.Net.WebClient).DownloadFile($strLinkx86, "$strTempDirectory\$strChromeVersion\GoogleChromeStandaloneEnterprise.msi")
    Start-Sleep -Seconds 5
    Write-host "Downloaded Chrome $Script:strChromeVersion" -ForegroundColor Yellow
    } catch {
        Write-Host 'Download failed. There was a problem with the download.' -ForegroundColor Red
        exit
    } 

    #get Product Code for both versions
    Import-Module .\Get-MSIFileInformation.ps1 -Force
    $strProductCodex64 = (MSIInfo -Path "$Script:strTempDirectory\$Script:strChromeVersion\GoogleChromeStandaloneEnterprise64.msi" -Property ProductCode) | Out-String
    $strProductCodex86 = (MSIInfo -Path "$Script:strTempDirectory\$Script:strChromeVersion\GoogleChromeStandaloneEnterprise.msi" -Property ProductCode) | Out-String
    $Script:strProductCodex64 = $strProductCodex64.Replace('{','').Replace('}','')
    $Script:strProductCodex86 = $strProductCodex86.Replace('{','').Replace('}','')
    #Set-Variable -Name strProductCodex64 -Value ($strProductCodex64) -Scope Script
    #et-Variable -Name strProductCodex86 -Value ($strProductCodex86) -Scope Script
    Write-Host "Gathered the following Product Codes." -ForegroundColor Yellow
    Write-Host "x64: $Script:strProductCodex64" -ForegroundColor Green
    Write-Host "x86: $Script:strProductCodex86" -ForegroundColor Green
}

Function CreateBatch {
#create installer/removal scipts
$installbatch=@'
@echo off
taskkill /IM chrome.exe /f 2> nul
:CheckOS
IF EXIST "%PROGRAMFILES(X86)%" (GOTO 64BIT) ELSE (GOTO 32BIT)
:64BIT
msiexec /i "%~dp0GoogleChromeStandaloneEnterprise64.msi" /qn /norestart REINSTALLMODE=vomus
GOTO END
:32BIT
msiexec /i "%~dp0GoogleChromeStandaloneEnterprise.msi" /qn /norestart REINSTALLMODE=vomus
GOTO END
:END
'@

$uninstallbatch=@'
wmic product where "name like 'Google Chrome'" call uninstall
'@

$installbatch | out-file $strTempDirectory\$strChromeVersion\install.bat -Encoding ascii
$uninstallbatch | out-file $strTempDirectory\$strChromeVersion\uninstall.bat -Encoding ascii
Write-Host "Built batch installer scripts" -ForegroundColor Yellow
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
Set-Location "$($Script:strSiteCode):\" @initParams

#Update Collection membership rules for Outdated Chrome
$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_INSTALLED_SOFTWARE on SMS_G_System_INSTALLED_SOFTWARE.ResourceID = SMS_R_System.ResourceId where SMS_G_System_INSTALLED_SOFTWARE.ProductName like 'Google Chrome%' and SMS_G_System_INSTALLED_SOFTWARE.ProductVersion < '$strChromeVersion'"
remove-CMDeviceCollectionQueryMembershipRule -CollectionName $Script:strOutdatedColl -RuleName 'Outdated' -Force
add-CMDeviceCollectionQueryMembershipRule -CollectionName $Script:strOutdatedColl -RuleName "Outdated" -QueryExpression $query

#Build updated Detection Method Clauses
$clause1 = New-CMDetectionClauseWindowsInstaller -ProductCode $Script:strProductCodex64 -Existence
$clause2 = New-CMDetectionClauseWindowsInstaller -ProductCode $Script:strProductCodex86 -Existence
$clause1.Connector = 'Or'
$clause2.Connector = 'Or'
#pulling Package information to update
$Script:strCurrentPkg = (Get-CMApplication -Name $strCurrentPkgName)
$strAppMgmt = ([xml]$CurrentPkg.SDMPackageXML).AppMgmtDigest
$strDeploymentType = $strAppMgmt.DeploymentType | select -First 1
$strPreviousLocation = $strDeploymentType.Installer.Contents.Content.Location
$SDMPackageXML = (Get-CMDeploymentType -ApplicationName "$($strCurrentPkgName)" -DeploymentTypeName "$($strCurrentPkgName)").SDMPackageXML
[string[]]$strOldDetections = (([regex]'(?<=SettingLogicalName=.)([^"]|\\")*').Matches($SDMPackageXML)).Value
#paramaters set, populatating chagnes in SCCM now
Write-Host "Updating Deployment Packages" -ForegroundColor Yellow
Set-CMApplication -Name $Script:strCurrentPkgName -SoftwareVersion $Script:strChromeVersion
Set-CMScriptDeploymentType -ApplicationName $Script:strCurrentPkgName -DeploymentTypeName $Script:strCurrentPkgName -ContentLocation $Script:strFinalDirectory\$Script:strChromeVersion -RemoveDetectionClause $strOldDetections -AddDetectionClause($clause1,$clause2)
Set-CMScriptDeploymentType -ApplicationName $Script:strPreviousPkgName -DeploymentTypeName $Script:strPreviousPkgName -ContentLocation $Script:strPreviousLocation
Write-Host "Redistributing Content" -ForegroundColor Yellow
Update-CMDistributionPoint -ApplicationName $Script:strCurrentPkgName -DeploymentTypeName $Script:strCurrentPkgName
#re-schedule deployments
$strServerDate = @(@(0..7) | % {$(Get-Date 18:00:00).AddDays($_)} | ? {$_.DayOfWeek -ieq "Friday"})[0]
Write-Host "Reset deployment deadlines:" -ForegroundColor Yellow
Write-Host "Starting at below times, during maintenance window"  -ForegroundColor Yellow
Set-CMApplicationDeployment -ApplicationName $Script:strCurrentPkgName -CollectionName $Script:strPilotColl -AvailableDateTime (get-date 06:00:00).AddDays(0) -DeadlineDateTime (get-date 18:00:00).AddDays(0)
Write-Host " - Pilot : "(get-date 18:00:00).AddDays(0) -ForegroundColor Yellow
Set-CMApplicationDeployment -ApplicationName $Script:strCurrentPkgName -CollectionName $Script:strWkstAll -AvailableDateTime (get-date 06:00:00).AddDays(0)  -DeadlineDateTime (get-date 18:00:00).AddDays(2)
Write-Host " - All Wkst : "(get-date 18:00:00).AddDays(2) -ForegroundColor Yellow
Set-CMApplicationDeployment -ApplicationName $Script:strCurrentPkgName -CollectionName $Script:strServerAll -AvailableDateTime (get-date 06:00:00).AddDays(0) -DeadlineDateTime $strServerDate
Write-Host " - All Server : "$strServerDate -ForegroundColor Yellow
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
    if((Get-PSDrive -Name $Script:strSiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
        New-PSDrive -Name $Script:strSiteCode -PSProvider CMSite -Root $Script:strProviderMachineName @initParams
        }
    Set-Location "$($strSiteCode):\" @initParams
            
    #Build updated Detection Method Clauses
        $clause1 = New-CMDetectionClauseWindowsInstaller -ProductCode $Script:strProductCodex64 -Existence
        $clause2 = New-CMDetectionClauseWindowsInstaller -ProductCode $Script:strProductCodex86 -Existence
        $clause1.Connector = 'Or'
        $clause2.Connector = 'Or'
    #paramaters set, populatating changes in SCCM now
        Write-Host "Creating Deployment Packages" -ForegroundColor Yellow
        New-CMApplication -Name $Script:strCurrentPkgName -SoftwareVersion $Script:strChromeVersion
        Add-CMScriptDeploymentType -ApplicationName $Script:strCurrentPkgName -DeploymentTypeName $Script:strCurrentPkgName -ContentLocation $Script:strFinalDirectory\$strChromeVersion -AddDetectionClause($clause1,$clause2) -InstallCommand "install.bat" -UninstallCommand "uninstall.bat"
        Write-Host "Distributing Content" -ForegroundColor Yellow
        Update-CMDistributionPoint -ApplicationName $Script:strPreviousPkgName -DeploymentTypeName $Script:strPreviousPkgName
        Update-CMDistributionPoint -ApplicationName $Script:strCurrentPkgName -DeploymentTypeName $Script:strCurrentPkgName
    #return to local disk
        sl c:
        
}




GetVersion
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