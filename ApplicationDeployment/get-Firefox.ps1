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
 
if (!(get-psdrive -PSProvider CMSite -ErrorAction SilentlyContinue)) {. ..\set-sccmsite.ps1}
$Script:TempDirectory = $env:TEMP #inital download directory
$Script:CurrentPkgName = "Mozilla Firefox"
$Script:FirefoxColl = "Deploy | Mozilla Firefox"
$Script:FirefoxOutDateColl = "Query | Firefox Outdated"
$Script:FirefoxVersion = $null
$SourceShare = "\\$ProviderMachineName\Source$"
$Script:FinalDirectory = "$SourceShare\Software\Firefox"

#Checking for destination directory
If (!(Test-Path -Path $Script:FinalDirectory)){
    Write-Host "Unable to locate destination directory, attempting to create..." -ForegroundColor Yellow
    try {new-item -ItemType Directory -Path $Script:FinalDirectory | Out-Null; Write-Host -ForegroundColor Green "Success!"}
    catch {Write-Host -ForegroundColor Red "Unable to create $Script:FinalDirectory - must exit now"; exit 0}
}

Function GetVersion {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ie = New-Object -com internetexplorer.application
    $url = "https://www.mozilla.org/en-US/firefox/notes/"
    $ie.navigate($url)
    while ($ie.Busy -eq $true) { Start-Sleep -Seconds 2; }
    $titles = $ie.Document.body.getElementsByClassName('c-release-version')
    foreach ($storyTitle in $titles) {
         $FirefoxVersion = $storyTitle.innerText
    }
    Set-Variable -Name FirefoxVersion -Value ($FirefoxVersion) -Scope Script
    
    #kills ie after running
    $ie.Quit()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($ie) | Out-Null
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    
    If (!($Script:FirefoxVersion)){Write-Output "Firefox Version undetected, exiting"; exit}

    If (!(Test-Path -Path $Script:FinalDirectory\$Script:FirefoxVersion)){
        Write-Host "New Version Needed, Firefox $Script:FirefoxVersion downloading now." -ForegroundColor Yellow
    }
    else {
        Write-Host "Latest Version ($Script:FirefoxVersion) already deployed." -ForegroundColor Yellow
        exit
    }
}
Function GetFirefox {
    # Test internet connection
if (Test-Connection download.mozialla.com -Count 3 -Quiet) {
    Write-Host "Dwnloading files." -ForegroundColor Yellow
    }
    
    # Download the installer from Mozzilla
try {
    $Linkx64 = 'https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US'
	New-Item -ItemType Directory "$Script:TempDirectory\$Script:FirefoxVersion" -Force | Out-Null
    (New-Object System.Net.WebClient).DownloadFileAsync($Linkx64, "$Script:TempDirectory\$Script:FirefoxVersion\MozillaFirefox64.exe")
    Start-Sleep -Seconds 5
    Write-host "Files Downloaded to $Script:TempDirectory\$Script:FirefoxVersion" -ForegroundColor Yellow
    } catch {
        Write-Host 'Download failed. There was a problem with the download.' -ForegroundColor Red
        exit
    } 

}
Function UpdateFiles {
    Write-Host "Uploading to Source's Share ($Script:FinalDirectory\$Script:FirefoxVersion)" -ForegroundColor Yellow
    try {
        # Copy the installer to server
        Copy-item -Container -Recurse "$Script:TempDirectory\$Script:FirefoxVersion" $Script:FinalDirectory
        } catch {
        Write-Host "Upload failed. You will have to move the installer yourself from $Script:TempDirectory" -ForegroundColor Red
    }
}

#update deployment package on SCCM to current version, and redistribute
Function SetSCCMDeployment {
    param ([switch]$FirstRun)
    
    Write-Host "Connecting to SCCM Site Server" -ForegroundColor Yellow
    $curLoc = (Get-Location)
    Set-Location "$($SiteCode):\" @initParams


#Update Collection membership rules for Outdated Chrome
$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_INSTALLED_SOFTWARE on SMS_G_System_INSTALLED_SOFTWARE.ResourceID = SMS_R_System.ResourceId where SMS_G_System_INSTALLED_SOFTWARE.ProductName like 'Mozilla Firefox%' and SMS_G_System_INSTALLED_SOFTWARE.ProductVersion < '$Script:FirefoxVersion'"
if ($FirstRun){
    if (!(test-path "DeviceCollection\AppQueries")) {Write-Host -ForegroundColor Yellow "Creating AppQueries Folder, Console needs to be restarted if open" ; new-item -Name "AppQueries" -Path $($SiteCode+":\DeviceCollection")}
    if (!(test-path "DeviceCollection\AppDeployments")) {Write-Host -ForegroundColor Yellow "Creating AppDeployments Folder, Console needs to be restarted if open" ; new-item -Name 'AppDeployments' -Path $($SiteCode+":\DeviceCollection")}
    New-CMDeviceCollection -LimitingCollectionName "All Desktop and Server Clients" -Name $Script:FirefoxOutDateColl
    Add-CMDeviceCollectionQueryMembershipRule -CollectionName $Script:FirefoxOutDateColl -RuleName "Firefox Outdated" -QueryExpression $query
    New-CMDeviceCollection -LimitingCollectionName "All Desktop and Server Clients" -Name $Script:FirefoxColl
    Add-CMDeviceCollectionIncludeMembershipRule -CollectionName $Script:FirefoxColl -IncludeCollectionName $Script:FirefoxOutDateColl
    Move-CMObject -FolderPath "DeviceCollection\AppQueries" -InputObject (Get-CMDeviceCollection -Name $Script:FirefoxOutDateColl)
    Move-CMObject -FolderPath "DeviceCollection\AppDeployments" -InputObject (Get-CMDeviceCollection -Name $Script:FirefoxColl)   
} else {
    remove-CMDeviceCollectionQueryMembershipRule -CollectionName $Script:FirefoxOutDateColl -RuleName "Firefox Outdated" -Force -ErrorAction SilentlyContinue
    add-CMDeviceCollectionQueryMembershipRule -CollectionName $Script:FirefoxOutDateColl -RuleName "Firefox Outdated" -QueryExpression $query -Force
}

#Build updated Detection Method Clauses
$clause1 = New-CMDetectionClauseFile -Value -Path "%ProgramFiles%\Mozilla Firefox\" -FileName "Firefox.exe" -PropertyType Version -ExpressionOperator GreaterEquals -ExpectedValue $Script:FirefoxVersion
if (!($FirstRun)){
    #pulling Package information to update
    $SDMPackageXML = (Get-CMDeploymentType -ApplicationName "$($Script:CurrentPkgName)" -DeploymentTypeName "$($Script:CurrentPkgName)").SDMPackageXML
    [string[]]$OldDetections = (([regex]'(?<=SettingLogicalName=.)([^"]|\\")*').Matches($SDMPackageXML)).Value
} 
#paramaters set, populatating chagnes in SCCM now
if ($FirstRun){
    New-CMApplication -Name $Script:CurrentPkgName -AutoInstall $true -Description $Script:CurrentPkgName -SoftwareVersion $Script:FirefoxVersion
    Add-CMScriptDeploymentType -ApplicationName $Script:CurrentPkgName -DeploymentTypeName $Script:CurrentPkgName -ContentLocation $Script:FinalDirectory\$Script:FirefoxVersion -InstallCommand "install.bat" -InstallationBehaviorType InstallForSystem -AddDetectionClause $clause1
    Start-CMContentDistribution -ApplicationName $Script:CurrentPkgName -DistributionPointGroupName $((Get-CMDistributionPointGroup).Name)
    New-CMApplicationDeployment -CollectionName $Script:FirefoxColl -ApplicationName $Script:CurrentPkgName -DeployAction Install -DeployPurpose Required -UserNotification DisplaySoftwareCenterOnly -AvailableDateTime (get-date 06:00:00).AddDays(0) -DeadlineDateTime (get-date 18:00:00).AddDays(1) -TimeBaseOn LocalTime
} else {
    Write-Host "Updating Deployment Packages" -ForegroundColor Yellow
    Set-CMApplication -Name $Script:CurrentPkgName -SoftwareVersion $Script:FirefoxVersion
    Set-CMScriptDeploymentType -ApplicationName $Script:CurrentPkgName -DeploymentTypeName $Script:CurrentPkgName -ContentLocation $Script:FinalDirectory\$Script:FirefoxVersion -RemoveDetectionClause $OldDetections -AddDetectionClause($clause1)
    Write-Host "Redistributing Content" -ForegroundColor Yellow
    Update-CMDistributionPoint -ApplicationName $Script:CurrentPkgName -DeploymentTypeName $Script:CurrentPkgName
    Set-CMApplicationDeployment -ApplicationName $Script:CurrentPkgName -CollectionName $Script:FirefoxColl -AvailableDateTime (get-date 06:00:00).AddDays(0) -DeadlineDateTime (get-date 18:00:00).AddDays(1)
}

#return to local disk
Set-Location $curLoc
}

Function CreateBatch {
Write-Host "Building batch installer scripts" -ForegroundColor Yellow
#create installer/removal scipts
$installbatch=@'
@echo off
taskkill /IM firefox.exe /f 2> nul
:CheckOS
IF EXIST "%PROGRAMFILES(X86)%" (GOTO 64BIT) ELSE (GOTO END)
:64BIT
"%~dp0MozillaFirefox64.exe" -ms
if exist "%programfiles%\Mozilla Firefox\" copy /Y "%~dp0override.ini" "%programfiles%\Mozilla Firefox\browser\"
if exist "%programfiles%\Mozilla Firefox\" copy /Y "%~dp0mozilla.cfg" "%programfiles%\Mozilla Firefox\"
if exist "%programfiles%\Mozilla Firefox\" copy /Y "%~dp0local-settings.js" "%programfiles%\Mozilla Firefox\defaults\pref"
if exist "%programfiles%\Mozilla Firefox\" copy /Y "%~dp0trustwubcerts.js" "%programfiles%\Mozilla Firefox\defaults\pref"
GOTO END

:END
exit /B %EXIT_CODE%
'@



$uninstallbatch=@'
@echo off
taskkill /IM Firefox.exe /f 2> nul
:CheckOS
IF EXIST "%PROGRAMFILES(X86)%" (GOTO 64BIT) ELSE (GOTO 32BIT)
:64BIT
"C:\Program Files\Mozilla Firefox\uninstall\helper.exe" -ms
GOTO END

:32BIT
"C:\Program Files (x86)\Mozilla Firefox\uninstall\helper.exe" -ms
GOTO END

:END
exit /B %EXIT_CODE%
'@

$installbatch | out-file $Script:TempDirectory\$Script:FirefoxVersion\install.bat -Encoding ascii
$uninstallbatch | out-file $Script:TempDirectory\$Script:FirefoxVersion\uninstall.bat -Encoding ascii
}




GetVersion
GetFirefox
CreateBatch
UpdateFiles
If ($FirstRun){SetSCCMDeployment -FirstRun} Else {SetSCCMDeployment} 
Write-Host "Complete!" -ForegroundColor Yellow