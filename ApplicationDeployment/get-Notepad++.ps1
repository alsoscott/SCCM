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
$Script:FinalDirectory = "\\server\share" #final destination for Notepad++ installers
$SiteCode = "SMSSiteCode" # SCCM Site code 
$ProviderMachineName = "SCCM Site Server" # SMS Provider machine name
$Script:CurrentPkgName = "Notepad++ - Current"
$Script:strDeployColl = "Deploy | Notepad++"
#Checking for destination directory
If (!(Test-Path -Path $Script:FinalDirectory)){
    Write-Host "Unable to locate destination directory, exiting..." -ForegroundColor Red
    exit
}

Function GetVersion {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ie = New-Object -com internetexplorer.application
    $url = "https://notepad-plus-plus.org/download/"
    $ie.navigate($url)
    while ($ie.Busy -eq $true) { Start-Sleep -Milliseconds 100; }
    $titles = $ie.Document.body.getElementsByTagName('H1')
    foreach ($storyTitle in $titles) {
         $NotepadPlusVersion = $storyTitle.innerText | Select-String "\d+\.\d+\.\d+\.?" -AllMatches |
         foreach {$_.Matches} | foreach {$_.Value}         
    }
    If (!($NotepadPlusVersion)){Write-Host "Version not found." -ForegroundColor Yellow; exit 1}
        If (!(Test-Path -Path $Script:FinalDirectory\$NotepadPlusVersion)){
        Write-Host "New Version Needed, Notepad++ $NotepadPlusVersion downloading now." -ForegroundColor Yellow
    }
    else {
        Write-Host "Latest Version ($NotepadPlusVersion) already deployed." -ForegroundColor Yellow
        exit
    }
}
Function GetNotepad++ {
    # Test internet connection
if (Test-Connection notepad-plus-plus.org -Count 3 -Quiet) {
    Write-Host "Dwnloading files." -ForegroundColor Yellow
    }
    
    # Download the installer from Mozzilla
try {
    $MajorVersion = $NotepadPlusVersion[0]
    $MinorVersion = $NotepadPlusVersion[2]
    $SubVersion = $NotepadPlusVersion[4]
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ie = New-Object -com internetexplorer.application
    $url = "https://notepad-plus-plus.org/repository/$MajorVersion.x/$MajorVersion.$MinorVersion.$SubVersion"
    $Filex86 = "npp.$MajorVersion.$MinorVersion.$SubVersion.Installer.exe"
    $Filex64 = "npp.$MajorVersion.$MinorVersion.$SubVersion.Installer.x64.exe"
    $ie.navigate($url)
    $Linkx64 = "$url/$Filex64"
    $Linkx86 = "$url/$Filex86"
    
    New-Item -ItemType Directory "$TempDirectory\$NotepadPlusVersion" -Force | Out-Null
    (New-Object System.Net.WebClient).DownloadFileAsync($Linkx64, "$TempDirectory\$NotepadPlusVersion\Notepad++64.exe")
    (New-Object System.Net.WebClient).DownloadFileAsync($Linkx86, "$TempDirectory\$NotepadPlusVersion\Notepad++32.exe")
    Start-Sleep -Seconds 5
    Write-host "Files Downloaded to $TempDirectory\$NotepadPlusVersion" -ForegroundColor Yellow
    } catch {
        Write-Host 'Download failed. There was a problem with the download.' -ForegroundColor Red
        exit
    } 

}
Function UpdateFiles {
    Write-Host "Uploading to Source's Share ($Script:FinalDirectory\$NotepadPlusVersion)" -ForegroundColor Yellow
    try {
        # Copy the installer to server
        Copy-item -Container -Recurse "$TempDirectory\$NotepadPlusVersion" $Script:FinalDirectory
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
$clause1 = New-CMDetectionClauseFile -Value -Path "%ProgramFiles%\Notepad++\" -FileName "notepad++.exe" -PropertyType Version -ExpressionOperator GreaterEquals -ExpectedValue $NotepadPlusVersion
$clause2 = New-CMDetectionClauseFile -Value -Path "%ProgramFiles(x86)%\Notepad++\" -FileName "notepad++.exe" -PropertyType Version -ExpressionOperator GreaterEquals -ExpectedValue $NotepadPlusVersion 
$clause1.Connector = 'Or'
$clause2.Connector = 'Or'
#pulling Package information to update
#$CurrentPkg = (Get-CMApplication -Name $Script:CurrentPkgName)
#$AppMgmt = ([xml]$CurrentPkg.SDMPackageXML).AppMgmtDigest
#$DeploymentType = $AppMgmt.DeploymentType | select -First 1
#$PreviousLocation = $DeploymentType.Installer.Contents.Content.Location
$SDMPackageXML = (Get-CMDeploymentType -ApplicationName "$($Script:CurrentPkgName)" -DeploymentTypeName "$($Script:CurrentPkgName)").SDMPackageXML
[string[]]$OldDetections = (([regex]'(?<=SettingLogicalName=.)([^"]|\\")*').Matches($SDMPackageXML)).Value
#paramaters set, populatating chagnes in SCCM now
Write-Host "Updating Deployment Packages" -ForegroundColor Yellow
Set-CMApplication -Name $Script:CurrentPkgName -SoftwareVersion $NotepadPlusVersion
Set-CMScriptDeploymentType -ApplicationName $Script:CurrentPkgName -DeploymentTypeName $Script:CurrentPkgName -ContentLocation $Script:FinalDirectory\$NotepadPlusVersion -RemoveDetectionClause $OldDetections -AddDetectionClause($clause1,$clause2)
#Set-CMScriptDeploymentType -ApplicationName $PreviousPkgName -DeploymentTypeName $PreviousPkgName -ContentLocation $PreviousLocation
Write-Host "Redistributing Content" -ForegroundColor Yellow
Update-CMDistributionPoint -ApplicationName $Script:CurrentPkgName -DeploymentTypeName $Script:CurrentPkgName
#re-schedule deployments
Set-CMApplicationDeployment -ApplicationName $Script:CurrentPkgName -CollectionName $Script:strDeployColl -AvailableDateTime (get-date 06:00:00).AddDays(0) -DeadlineDateTime (get-date 18:00:00).AddDays(0)
#return to local disk
sl c:
}

Function CreateBatch {
Write-Host "Building batch installer scripts" -ForegroundColor Yellow
#create installer/removal scipts
$installbatch=@'
@echo off
taskkill /IM notepad++.exe /f 2> nul
:CheckOS
IF EXIST "%PROGRAMFILES(X86)%" (GOTO 64BIT) ELSE (GOTO 32BIT)
:64BIT
"%~dp0Notepad++64.exe" /S
GOTO END
:32BIT
"%~dp0Notepad++32.exe" /S
GOTO END

:END
exit /B %EXIT_CODE%
'@



$uninstallbatch=@'
@echo off
taskkill /IM notepad++.exe /f 2> nul
:CheckOS
IF EXIST "%PROGRAMFILES(X86)%" (GOTO 64BIT) ELSE (GOTO 32BIT)
:64BIT
%ProgramFiles%\Notepad++\uninstall.exe /S
GOTO END

:32BIT
%ProgramFiles(x86)%\Notepad++\uninstall.exe /S
GOTO END

:END
exit /B %EXIT_CODE%
'@


$installbatch | out-file $TempDirectory\$NotepadPlusVersion\install.bat -Encoding ascii
$uninstallbatch | out-file $TempDirectory\$NotepadPlusVersion\uninstall.bat -Encoding ascii

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
       
        #Build updated Detection Method Clauses
        $clause1 = New-CMDetectionClauseFile -Value -Path "%ProgramFiles%\Notepad++\" -FileName "Notepad++.exe" -PropertyType Version -ExpressionOperator GreaterEquals -ExpectedValue $NotepadPlusVersion
        $clause2 = New-CMDetectionClauseFile -Value -Path "%ProgramFiles(x86)%\Notepad++\" -FileName "Notepad++.exe" -PropertyType Version -ExpressionOperator GreaterEquals -ExpectedValue $NotepadPlusVersion 
        $clause1.Connector = 'Or'
        $clause2.Connector = 'Or'
        #paramaters set, populatating chagnes in SCCM now
        Write-Host "Creating Deployment Packages" -ForegroundColor Yellow
        New-CMApplication -Name $Script:CurrentPkgName -SoftwareVersion $NotepadPlusVersion
        Add-CMScriptDeploymentType -ApplicationName $Script:CurrentPkgName -DeploymentTypeName $Script:CurrentPkgName -ContentLocation $Script:FinalDirectory\$NotepadPlusVersion -AddDetectionClause($clause1,$clause2) -InstallCommand "install.bat" -UninstallCommand "uninstall.bat"
        #Add-CMScriptDeploymentType -ApplicationName $PreviousPkgName -DeploymentTypeName $PreviousPkgName -ContentLocation $PreviousLocation -AddDetectionClause($clause1,$clause2)
        Write-Host "Distributing Content" -ForegroundColor Yellow
        Start-CMContentDistribution -ApplicationName $Script:CurrentPkgName -DistributionPointName $ProviderMachineName
        #return to local disk
        sl c:
        
}

GetVersion
GetNotepad++
CreateBatch
UpdateFiles
If ($FirstRun){
   FirstRun
}
Else {
    SetSCCMDeployment
} 
Write-Host "Complete!" -ForegroundColor Yellow