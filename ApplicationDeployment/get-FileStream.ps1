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
$Script:strTempDirectory = $env:TEMP #inital download directory
$Script:strFinalDirectory = "\\server\share" #final destination for Notepad++ installers
$Script:strSiteCode = "SMSSiteCode" # SCCM Site code 
$Script:strProviderMachineName = "SCCM Site Server" # SMS Provider machine name
$Script:strCurrentPkgName = "Google DriveFileStream - Current"
$Script:strFileStreamVersion = $null

#Checking for destination directory
If (!(Test-Path -Path $Script:strFinalDirectory)){
    Write-Host "Unable to locate destination directory, exiting..." -ForegroundColor Red
    exit
}
Function GetFileStream {
    # Test internet connection
if (Test-Connection dl.google.com -Count 3 -Quiet) {
    Write-Host "Downloading files." -ForegroundColor Yellow
    }
    
    # Download the installer from Google
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $url = "https://dl.google.com/drive-file-stream/GoogleDriveFSSetup.exe"
    $File = "GoogleDriveFSSetup.exe"
    #$Link = "$url"
    if (!(Test-Path -Path $Script:strTempDirectory\GoogleDriveTemp)){New-Item -ItemType Directory -Path $Script:strTempDirectory\GoogleDriveTemp | Out-Null}
    (New-Object System.Net.WebClient).DownloadFile($url, "$Script:strTempDirectory\GoogleDriveTemp\GoogleDriveFSSetup.exe")
    Copy-Item $Script:strFinalDirectory\asrs-chain.pem -Destination $Script:strTempDirectory\GoogleDriveTemp\asrs-chain.pem -Force
    Start-Sleep -Seconds 5
    Write-host "Files Downloaded to $Script:strTempDirectory\GoogleDriveTemp\$File" -ForegroundColor Yellow
    $Script:strFileStreamVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo("$Script:strTempDirectory\GoogleDriveTemp\$File").FileVersion
    If (!($Script:strFileStreamVersion)){Write-Output "DriveFS Version undetected, exiting"; exit}



    } catch {
        Write-Host 'Download failed. There was a problem with the download.' -ForegroundColor Red
        exit
    } 
}

Function InstallScripts{
$InstallPS1=@'
$PendingReboot = Test-Path "c:\program Files\Google\Drive File Stream\rebootpending"
$regPath = 'HKLM:\SOFTWARE\Policies\Google\DriveFS'
$certpath = 'C:\Program Files\Google\Drive File Stream\asrs-chain.pem'

If ($PendingReboot -eq "True") {
        [System.Environment]::Exit(1641)
    }


cmd /c .\GoogleDriveFSSetup.exe --silent
If (!(test-path $RegPath)) {
    New-Item -Path $regPath
    New-ItemProperty -path $RegPath -Name "TrustedRootCertificate" -Value $certpath
    }
If (!(Test-Path $certpath)){
        Copy-Item .\asrs-chain.pem -Destination $certpath
    }
cmd /c schtasks.exe /Change /TN "GoogleUpdateTaskMachineCore" /Disable
cmd /c schtasks.exe /Change /TN "GoogleUpdateTaskMachineUA" /Disable
'@

$UninstallPS1=@'
$gdrive = get-itemproperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' | Select-Object DisplayName, DisplayVersion, UninstallString, PSChildName | Where-Object { $_.DisplayName -match "Google Drive File Stream"}
if ($gdrive) {
    $Uninstall = $gdrive.UninstallString
    $Uninstall = """$Uninstall""" + " --silent"
    & cmd /c $Uninstall}

Start-Sleep 60
$PendingReboot = Test-Path "c:\program Files\Google\Drive File Stream\rebootpending"
If ($PendingReboot -eq "True") {
        write-host "Pending Reboot"
        exit
    }
$LastExitCode = 3010
'@

#Output Install and Uninstall scripts
$InstallPS1 | out-file $Script:strTempDirectory\GoogleDriveTemp\install.ps1 -Encoding ascii
$UninstallPS1 | out-file $Script:strTempDirectory\GoogleDriveTemp\uninstall.ps1 -Encoding ascii
}

function UploadFiles {
    If (!(Test-Path -Path $Script:strFinalDirectory\$Script:strFileStreamVersion)){
        Write-Host "New Version Needed, Drive File Stream $Script:strFileStreamVersion Uploading to Source's Share ($Script:strFinalDirectory\$Script:strFileStreamVersion)" -ForegroundColor Yellow
            try {
                # Copy the installer to server
                New-Item -ItemType Directory "$Script:strFinalDirectory\$Script:strFileStreamVersion" -Force | Out-Null
                Copy-item -Container -Recurse "$Script:strTempDirectory\GoogleDriveTemp\*" $Script:strFinalDirectory\$Script:strFileStreamVersion\
                } catch {
                Write-Host "Upload failed. You will have to move the installer yourself from $Script:strTempDirectory" -ForegroundColor Red
            }
        }
    
    else {
        Write-Host "Latest Version ($Script:strFileStreamVersion) already deployed." -ForegroundColor Yellow
        exit
    }    
}    

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
        
    #Build updated Detection Method Clauses
    $clause1 = New-CMDetectionClauseFile -Value -Path "%ProgramFiles%\Google\Drive File Stream\$Script:strFileStreamVersion\" -FileName "GoogleDriveFS.exe" -PropertyType Version -ExpressionOperator GreaterEquals -ExpectedValue $Script:strFileStreamVersion
    $clause2 = New-CMDetectionClauseFile -Value -Path "%ProgramFiles(x86)%\Google\Drive File Stream\$Script:strFileStreamVersion\" -FileName "GoogleDriveFS.exe" -PropertyType Version -ExpressionOperator GreaterEquals -ExpectedValue $Script:strFileStreamVersion 
    $clause1.Connector = 'Or'
    $clause2.Connector = 'Or'
    #pulling Package information to update
    #$CurrentPkg = (Get-CMApplication -Name $Script:strCurrentPkgName)
    #$AppMgmt = ([xml]$CurrentPkg.SDMPackageXML).AppMgmtDigest
    #$DeploymentType = $AppMgmt.DeploymentType | select -First 1
    #$PreviousLocation = $DeploymentType.Installer.Contents.Content.Location
    $SDMPackageXML = (Get-CMDeploymentType -ApplicationName "$($Script:strCurrentPkgName)" -DeploymentTypeName "$($Script:strCurrentPkgName)").SDMPackageXML
    [string[]]$OldDetections = (([regex]'(?<=SettingLogicalName=.)([^"]|\\")*').Matches($SDMPackageXML)).Value
    #paramaters set, populatating chagnes in SCCM now
    Write-Host "Updating Deployment Packages" -ForegroundColor Yellow
    Set-CMApplication -Name $Script:strCurrentPkgName -SoftwareVersion $Script:strFileStreamVersion
    Set-CMScriptDeploymentType -ApplicationName $Script:strCurrentPkgName -DeploymentTypeName $Script:strCurrentPkgName -ContentLocation $Script:strFinalDirectory\$Script:strFileStreamVersion -RemoveDetectionClause $OldDetections -AddDetectionClause($clause1,$clause2)
    #Set-CMScriptDeploymentType -ApplicationName $PreviousPkgName -DeploymentTypeName $PreviousPkgName -ContentLocation $PreviousLocation
    Write-Host "Redistributing Content" -ForegroundColor Yellow
    Update-CMDistributionPoint -ApplicationName $Script:strCurrentPkgName -DeploymentTypeName $Script:strCurrentPkgName

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
        Set-Location "$($Script:strSiteCode):\" @initParams
           
            #Build updated Detection Method Clauses
            $clause1 = New-CMDetectionClauseFile -Value -Path "%ProgramFiles%\Google\Drive File Stream\$Script:strFileStreamVersion\" -FileName "GoogleDriveFS.exe" -PropertyType Version -ExpressionOperator GreaterEquals -ExpectedValue $Script:strFileStreamVersion
            $clause2 = New-CMDetectionClauseFile -Value -Path "%ProgramFiles(x86)%\Google\Drive File Stream\$Script:strFileStreamVersion\" -FileName "GoogleDriveFS.exe" -PropertyType Version -ExpressionOperator GreaterEquals -ExpectedValue $Script:strFileStreamVersion 
            $clause1.Connector = 'Or'
            $clause2.Connector = 'Or'
            #paramaters set, populatating chagnes in SCCM now
            Write-Host "Creating Deployment Packages" -ForegroundColor Yellow
            New-CMApplication -Name $Script:strCurrentPkgName -SoftwareVersion $Script:strFileStreamVersion
            Add-CMScriptDeploymentType -ApplicationName $Script:strCurrentPkgName -DeploymentTypeName $Script:strCurrentPkgName -ContentLocation $Script:strFinalDirectory\$Script:strFileStreamVersion -AddDetectionClause($clause1,$clause2) -InstallCommand "install.ps1" -UninstallCommand "uninstall.ps1"
            #Add-CMScriptDeploymentType -ApplicationName $PreviousPkgName -DeploymentTypeName $PreviousPkgName -ContentLocation $PreviousLocation -AddDetectionClause($clause1,$clause2)
            Write-Host "Distributing Content" -ForegroundColor Yellow
            Start-CMContentDistribution -ApplicationName $Script:strCurrentPkgName -DistributionPointName $Script:strProviderMachineName
            #return to local disk
            sl c:
            
    }



#Versions to run
GetFileStream
InstallScripts
UploadFiles
If ($FirstRun){
   FirstRun
}
Else {
    SetSCCMDeployment
} 
Clear-Variable -Name "str*"
Write-Host "Complete!" -ForegroundColor Yellow