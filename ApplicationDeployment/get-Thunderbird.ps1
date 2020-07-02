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
$FinalDirectory = "\\server\share" #final destination for Thunderbird installers
$SiteCode = "SMSSiteCode" # SCCM Site code 
$ProviderMachineName = "SCCM Site Server" # SMS Provider machine name
$Script:strCurrentPkgName = "Mozilla Thunderbird"
$Script:strWkstAll = "Deploy | Thunderbird"
$Script:strOutdatedColl = "Query | Thunderbird Outdated" 

$Script:strThunderbirdVersion = $null

#Checking for destination directory
If (!(Test-Path -Path $FinalDirectory)){
    Write-Host "Unable to locate destination directory, exiting..." -ForegroundColor Red
    exit
}

Function GetVersion {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ie = New-Object -com internetexplorer.application
    $url = "https://www.mozilla.org/en-US/thunderbird/notes/"
    $ie.navigate($url)
    while ($ie.Busy -eq $true) { Start-Sleep -Milliseconds 100; }
    $titles = $ie.Document.body.getElementsByClassName('notes-head')
    foreach ($storyTitle in $titles) {
         $Script:strThunderbirdVersion = $storyTitle.innerText | Select-String "\d+\.\d+\.\d+\.?" |
            foreach {$_.Matches} | foreach {$_.Value}
         
    }

    If (!(Test-Path -Path $FinalDirectory\$Script:strThunderbirdVersion)){
        Write-Host "New Version Needed, Thunderbird $Script:strThunderbirdVersion downloading now." -ForegroundColor Yellow
    }
    else {
        Write-Host "Latest Version ($Script:strThunderbirdVersion) already deployed." -ForegroundColor Yellow
        exit
    }
}
Function GetThunderbird {
    # Test internet connection
if (Test-Connection download.mozialla.com -Count 3 -Quiet) {
    Write-Host "Dwnloading files." -ForegroundColor Yellow
    }
    
    # Download the installer from Mozzilla
try {
    $Linkx64 = 'https://download.mozilla.org/?product=Thunderbird-latest-ssl&os=win64&lang=en-US'
	$Linkx86 = 'https://download.mozilla.org/?product=Thunderbird-latest-ssl&os=win&lang=en-US'
    New-Item -ItemType Directory "$TempDirectory\$Script:strThunderbirdVersion" -Force | Out-Null
    (New-Object System.Net.WebClient).DownloadFileAsync($Linkx64, "$TempDirectory\$Script:strThunderbirdVersion\MozillaThunderbird64.exe")
    (New-Object System.Net.WebClient).DownloadFileAsync($Linkx86, "$TempDirectory\$Script:strThunderbirdVersion\MozillaThunderbird32.exe")
    Start-Sleep -Seconds 5
    Write-host "Files Downloaded to $TempDirectory\$Script:strThunderbirdVersion" -ForegroundColor Yellow
    } catch {
        Write-Host 'Download failed. There was a problem with the download.' -ForegroundColor Red
        exit
    } 

}
Function UpdateFiles {
    Write-Host "Uploading to Source's Share ($FinalDirectory\$Script:strThunderbirdVersion)" -ForegroundColor Yellow
    try {
        # Copy the installer to server
        Copy-item -Container -Recurse "$TempDirectory\$Script:strThunderbirdVersion" $FinalDirectory
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
$clause1 = New-CMDetectionClauseFile -Value -Path "%ProgramFiles%\Mozilla Thunderbird\" -FileName "Thunderbird.exe" -PropertyType Version -ExpressionOperator GreaterEquals -ExpectedValue $Script:strThunderbirdVersion
$clause2 = New-CMDetectionClauseFile -Value -Path "%ProgramFiles(x86)%\Mozilla Thunderbird\" -FileName "Thunderbird.exe" -PropertyType Version -ExpressionOperator GreaterEquals -ExpectedValue $Script:strThunderbirdVersion 
$clause1.Connector = 'Or'
$clause2.Connector = 'Or'
#pulling Package information to update
$SDMPackageXML = (Get-CMDeploymentType -ApplicationName "$($Script:strCurrentPkgName)" -DeploymentTypeName "$($Script:strCurrentPkgName)").SDMPackageXML
[string[]]$OldDetections = (([regex]'(?<=SettingLogicalName=.)([^"]|\\")*').Matches($SDMPackageXML)).Value
#paramaters set, populatating chagnes in SCCM now
Write-Host "Updating Deployment Packages" -ForegroundColor Yellow
Set-CMApplication -Name $Script:strCurrentPkgName -SoftwareVersion $Script:strThunderbirdVersion
Set-CMScriptDeploymentType -ApplicationName $Script:strCurrentPkgName -DeploymentTypeName $Script:strCurrentPkgName -ContentLocation $FinalDirectory\$Script:strThunderbirdVersion -RemoveDetectionClause $OldDetections -AddDetectionClause($clause1,$clause2)
Set-CMApplicationDeployment -ApplicationName $Script:strCurrentPkgName -CollectionName $Script:strWkstAll -AvailableDateTime (get-date 06:00:00).AddDays(0) -DeadlineDateTime (get-date 18:00:00).AddDays(1) -TimeBaseOn LocalTime -UserNotification DisplaySoftwareCenterOnly
Write-Host "Scheduled deadline of" (get-date 18:00:00).AddDays(1) "for collection " $Script:strWkstAll -ForegroundColor Yellow
Write-Host "Redistributing Content" -ForegroundColor Yellow
Update-CMDistributionPoint -ApplicationName $Script:strCurrentPkgName -DeploymentTypeName $Script:strCurrentPkgName

#Updating Outdated collection
$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_INSTALLED_SOFTWARE on SMS_G_System_INSTALLED_SOFTWARE.ResourceID = SMS_R_System.ResourceId where SMS_G_System_INSTALLED_SOFTWARE.ProductName like 'Mozilla Thunderbird%' and SMS_G_System_INSTALLED_SOFTWARE.ProductVersion < '$Script:strThunderbirdVersion'"
remove-CMDeviceCollectionQueryMembershipRule -CollectionName $Script:strOutdatedColl -RuleName 'Outdated' -Force
add-CMDeviceCollectionQueryMembershipRule -CollectionName $Script:strOutdatedColl -RuleName "Outdated" -QueryExpression $query
Write-Host "Creating limiting collection of outdated devices." -ForegroundColor Yellow


#return to local disk
sl c:
}

Function CreateBatch {
Write-Host "Copying installer scripts" -ForegroundColor Yellow
Copy-Item $FinalDirectory\set-thunderbird.ps1 $TempDirectory\$Script:strThunderbirdVersion

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
    
        #Outdated Collection
        New-CMDeviceCollection -LimitingCollectionName "All Desktop and Server Clients" -Name $Script:strOutdatedColl  -RefreshType Periodic
        $query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_INSTALLED_SOFTWARE on SMS_G_System_INSTALLED_SOFTWARE.ResourceID = SMS_R_System.ResourceId where SMS_G_System_INSTALLED_SOFTWARE.ProductName like 'Mozilla Thunderbird%' and SMS_G_System_INSTALLED_SOFTWARE.ProductVersion < '$Script:strThunderbirdVersion'"
        add-CMDeviceCollectionQueryMembershipRule -CollectionName $Script:strOutdatedColl -RuleName "Outdated" -QueryExpression $query
        Write-Host "Creating limiting collection of outdated devices." -ForegroundColor Yellow
        #Build Deployment Collection
        New-CMDeviceCollection -LimitingCollectionName "Workstations | All"  -Name $Script:strWkstAll  -RefreshType Periodic
        Add-CMDeviceCollectionIncludeMembershipRule -CollectionName $Script:strWkstAll -IncludeCollectionName $Script:strOutdatedColl
        Write-Host "Creating all collection." -ForegroundColor Yellow
        
        #Build updated Detection Method Clauses
        $clause1 = New-CMDetectionClauseFile -Value -Path "%ProgramFiles%\Mozilla Thunderbird\" -FileName "Thunderbird.exe" -PropertyType Version -ExpressionOperator GreaterEquals -ExpectedValue $Script:strThunderbirdVersion
        $clause2 = New-CMDetectionClauseFile -Value -Path "%ProgramFiles(x86)%\Mozilla Thunderbird\" -FileName "Thunderbird.exe" -PropertyType Version -ExpressionOperator GreaterEquals -ExpectedValue $Script:strThunderbirdVersion 
        $clause1.Connector = 'Or'
        $clause2.Connector = 'Or'
        #paramaters set, populatating chagnes in SCCM now
        Write-Host "Creating Deployment Packages" -ForegroundColor Yellow
        New-CMApplication -Name $Script:strCurrentPkgName -SoftwareVersion $Script:strThunderbirdVersion
        Add-CMScriptDeploymentType -ApplicationName $Script:strCurrentPkgName -DeploymentTypeName $Script:strCurrentPkgName -ContentLocation $FinalDirectory\$Script:strThunderbirdVersion -AddDetectionClause($clause1,$clause2) -InstallCommand '"set-thunderbird.ps1" -perform Install' -UninstallCommand '"set-thunderbird.ps1" -perform Uninstall'
        Write-Host "Distributing Content" -ForegroundColor Yellow
        Start-CMContentDistribution -ApplicationName $Script:strCurrentPkgName -DistributionPointName $ProviderMachineName
        New-CMApplicationDeployment -ApplicationName $Script:strCurrentPkgName -CollectionName $Script:strWkstAll -AvailableDateTime (get-date 06:00:00).AddDays(0) -DeadlineDateTime (get-date 18:00:00).AddDays(0) -TimeBaseOn LocalTime -DeployPurpose Required -UserNotification DisplaySoftwareCenterOnly
        #return to local disk
        sl c:
        
}

GetVersion
GetThunderbird
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