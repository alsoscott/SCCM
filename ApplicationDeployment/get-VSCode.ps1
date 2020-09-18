# Define the temporary location to cache the installer.
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
 
. ..\set-sccmsite.ps1
$Script:TempDirectory = $env:TEMP #inital download directory
#package names
$Script:CurrentPkgName = "VSCode"
$Script:DeployColl = "Deploy | VSCode"

#deployment collections
$Script:DeployColl = "Deploy | VSCode"
$Script:QueryOutDateColl = "Query | VSCode Outdated"

#reset ChromeVersion
$Script:VSCodeVersion = $null
#sets source share
$SourceShare = "\\$ProviderMachineName\Source$"
$Script:FinalDirectory = "$SourceShare\Software\VSCode"

#resets VSCodeVersion
$script:VSCodeVersion = $null

#Checking for destination directory
If (!(Test-Path -Path $Script:FinalDirectory)){
    Write-Host "Unable to locate destination directory, attempting to create: $Script:FinalDirectory" -ForegroundColor Yellow
    try {new-item -ItemType Directory -Path $Script:FinalDirectory ; Write-Host -ForegroundColor Green "Success!"}
    catch {Write-Host -ForegroundColor Red "Unable to create $Script:FinalDirectory - must exit now"; exit 0}
}

#checking for required external scripts
If (!(Test-Path -Path $PSScriptRoot\Get-MSIFileInformation.ps1)){
    Write-Host "MSI File Information Script not present.  If lost, download from https://www.scconfigmgr.com/2014/08/22/how-to-get-msi-file-information-with-powershell/ " -ForegroundColor Red
    exit
}

Function GetVersion {
[CmdletBinding()]
Param(
    [Parameter()]
    [ValidateSet('insider', 'stable')]
    [string[]] $Channel = @('stable'),
    [Parameter()]
    [ValidateSet('win32-x64')]
    [string[]] $Platform = @('win32-x64'),
    [Parameter()]
    [ValidateSet('https://update.code.visualstudio.com/api/update')]
    [string[]] $script:url = 'https://update.code.visualstudio.com/api/update'
    )

    # Output array
    $output = @()

    # Walk through each platform
    ForEach ($plat in ($Platform | Sort-Object)) {
        Write-Verbose "Getting release info for $plat."
        # Walk through each channel in the platform
        ForEach ($ch in $Channel) {
            try {
                Write-Verbose "Getting release info for $ch."
                $release = Invoke-WebRequest -Uri "$script:url/$plat/$ch/VERSION" -UseBasicParsing `
                    -ErrorAction SilentlyContinue
            }
            catch {
                Write-Error "Error connecting to $script:url/$plat/$ch/VERSION, with error $_"
                Break
            }
            finally {
                $releaseJson = $release | ConvertFrom-Json
                $script:VSCodeVersion = $releaseJson.productVersion
                [string]$script:url = $releaseJson.url ; Write-Output $script:url
                If (!($script:VSCodeVersion)){Write-Host "Version not found." -ForegroundColor Yellow; exit 1}
                If (!(Test-Path -Path $Script:FinalDirectory\$script:VSCodeVersion)){Write-Host "New Version Needed, VSCode $script:VSCodeVersion downloading now." -ForegroundColor Yellow}
                else {Write-Host "Latest Version ($script:VSCodeVersion) already deployed." -ForegroundColor Yellow; exit}
            
            }
        }
    }

}
Function GetVSCode {
    # Download the installer
    Write-host "Attempting to download version $script:VSCodeVersion to $Script:TempDirectory from $script:url" -ForegroundColor Yellow
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ie = New-Object -com internetexplorer.application
    New-Item -ItemType Directory "$TempDirectory\$script:VSCodeVersion" -Force | Out-Null
    (New-Object System.Net.WebClient).DownloadFile($script:url, "$TempDirectory\$script:VSCodeVersion\VSCode64.exe")
    Start-Sleep -Seconds 15
    Write-host "Files Downloaded to $TempDirectory\$script:VSCodeVersion" -ForegroundColor Yellow
    } 
    catch {Write-Host 'Download failed. There was a problem with the download.' -ForegroundColor Red; exit} 
}
Function SetInstaller {
    $installer=@'
    param ([parameter(Mandatory=$true)][string]$perform)
    if (!($perform)) {exit 1}
    if ($perform -eq "Install") {
        $strArgs = @("/silent","/CLOSEAPPLICATIONS","/RESTARTAPPLICATIONS")
        & "$(Get-Location)\VSCode64.exe" $strArgs
    }
    
    if ($perform -eq "Uninstall"){
        $strUninstall = "C:\Program Files\Microsoft VS Code\unins000.exe"
        $strArgs = "/silent"
        if (Test-path $strUninstall -ErrorAction SilentlyContinue){& $strUninstall $strArgs}
    }
'@
$installer | out-file $Script:TempDirectory\$Script:VSCodeVersion\set-vscode.ps1 -Encoding ascii   
}

Function UpdateFiles {
    Write-Host "Uploading to Source's Share ($Script:FinalDirectory\$script:VSCodeVersion)" -ForegroundColor Yellow
    try {
        # Copy the installer to server
        Copy-item -Container -Recurse "$TempDirectory\$script:VSCodeVersion" $Script:FinalDirectory
        } catch {
        Write-Host "Upload failed. You will have to move the installer yourself from $TempDirectory" -ForegroundColor Red
    }
}




#update deployment package on SCCM to current version, and redistribute
Function SetSCCMDeployment {
    param ([switch]$FirstRun)
    Write-Host "Connecting to SCCM Site Server" -ForegroundColor Yellow
    $curLoc = (Get-Location)
    Set-Location "$($SiteCode):\" @initParams
        
#Build updated Detection Method Clauses
$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_INSTALLED_SOFTWARE on SMS_G_System_INSTALLED_SOFTWARE.ResourceID = SMS_R_System.ResourceId where SMS_G_System_INSTALLED_SOFTWARE.ProductName = 'Microsoft Visual Studio Code' and SMS_G_System_INSTALLED_SOFTWARE.ProductVersion < '$script:VSCodeVersion'"
if ($FirstRun){
    if (!(test-path "DeviceCollection\AppQueries")) {Write-Host -ForegroundColor Yellow "Creating AppQueries Folder, Console needs to be restarted if open" ; new-item -Name "AppQueries" -Path $($SiteCode+":\DeviceCollection")}
    if (!(test-path "DeviceCollection\AppDeployments")) {Write-Host -ForegroundColor Yellow "Creating AppDeployments Folder, Console needs to be restarted if open" ; new-item -Name 'AppDeployments' -Path $($SiteCode+":\DeviceCollection")}
    New-CMDeviceCollection -LimitingCollectionName "All Desktop and Server Clients" -Name $Script:QueryOutDateColl
    Add-CMDeviceCollectionQueryMembershipRule -CollectionName $Script:QueryOutDateColl -RuleName "VSCode Outdated" -QueryExpression $query
    New-CMDeviceCollection -LimitingCollectionName "All Desktop and Server Clients" -Name $Script:DeployColl
    Add-CMDeviceCollectionIncludeMembershipRule -CollectionName $Script:DeployColl -IncludeCollectionName $Script:QueryOutDateColl
    Move-CMObject -FolderPath "DeviceCollection\AppQueries" -InputObject (Get-CMDeviceCollection -Name $Script:QueryOutDateColl)
    Move-CMObject -FolderPath "DeviceCollection\AppDeployments" -InputObject (Get-CMDeviceCollection -Name $Script:DeployColl)   
} else {
    remove-CMDeviceCollectionQueryMembershipRule -CollectionName $Script:QueryOutDateColl -RuleName "VSCode Outdated" -Force -ErrorAction SilentlyContinue
    add-CMDeviceCollectionQueryMembershipRule -CollectionName $Script:QueryOutDateColl -RuleName "VSCode Outdated" -QueryExpression $query -Force
}

$clause = New-CMDetectionClauseFile -Value -Path "%ProgramFiles%\Microsoft VS Code" -FileName "Code.exe" -PropertyType Version -ExpressionOperator GreaterEquals -ExpectedValue $script:VSCodeVersion
#pulling Package information to update
If (!($FirstRun)) {
    $SDMPackageXML = (Get-CMDeploymentType -ApplicationName "$($Script:CurrentPkgName)" -DeploymentTypeName "$($Script:CurrentPkgName)").SDMPackageXML
    [string[]]$OldDetections = (([regex]'(?<=SettingLogicalName=.)([^"]|\\")*').Matches($SDMPackageXML)).Value
}
if ($FirstRun){
    New-CMApplication -Name $Script:CurrentPkgName -AutoInstall $true -Description $Script:CurrentPkgName -SoftwareVersion $script:VSCodeVersion
    Add-CMScriptDeploymentType -ApplicationName $Script:CurrentPkgName -DeploymentTypeName $Script:CurrentPkgName -ContentLocation $Script:FinalDirectory\$script:VSCodeVersion -InstallCommand "set-vscode.ps1 -action Install" -UninstallCommand "set-vscode.ps1 -action Uninstall" -InstallationBehaviorType InstallForSystem -AddDetectionClause $clause
    Start-CMContentDistribution -ApplicationName $Script:CurrentPkgName -DistributionPointGroupName $((Get-CMDistributionPointGroup).Name)
    New-CMApplicationDeployment -CollectionName $Script:DeployColl -ApplicationName $Script:CurrentPkgName -DeployAction Install -DeployPurpose Required -UserNotification DisplaySoftwareCenterOnly -AvailableDateTime (get-date 06:00:00).AddDays(0) -DeadlineDateTime (get-date 18:00:00).AddDays(1) -TimeBaseOn LocalTime
} else {
    Write-Host "Updating Deployment Packages" -ForegroundColor Yellow
    Set-CMApplication -Name $Script:CurrentPkgName -SoftwareVersion $script:VSCodeVersion
    Set-CMScriptDeploymentType -ApplicationName $Script:CurrentPkgName -DeploymentTypeName $Script:CurrentPkgName -ContentLocation $Script:FinalDirectory\$script:VSCodeVersion -RemoveDetectionClause $OldDetections -AddDetectionClause($clause)
    Write-Host "Redistributing Content" -ForegroundColor Yellow
    Update-CMDistributionPoint -ApplicationName $Script:CurrentPkgName -DeploymentTypeName $Script:CurrentPkgName
    Set-CMApplicationDeployment -ApplicationName $Script:CurrentPkgName -CollectionName $Script:DeployColl -AvailableDateTime (get-date 06:00:00).AddDays(0) -DeadlineDateTime (get-date 18:00:00).AddDays(1)
}
#return to local disk
Set-location $curLoc
}


GetVersion
GetVSCode
SetInstaller
UpdateFiles
If ($FirstRun){SetSCCMDeployment -FirstRun} else {SetSCCMDeployment} 
Write-Host "Complete!" -ForegroundColor Yellow