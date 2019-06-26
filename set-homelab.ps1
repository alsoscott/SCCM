<#
************************************************************************************************************************
.SYNOPSIS
This is a Powershell script to build out a homelab.
 
Disclaimer: This script is provided "AS IS" with no warranties, confers no rights and is not supported by the author.
Author - Scott Churchill
Contact - Various places on internet as AlsoScott

.DESCRIPTION
Includes Domain Controller and WSUS so far, plans to include SQL Server and Configuration Manager as well
Designed to be run on Server Core 

.EXAMPLE
./set-homelab.ps1 (plans to add future functionality here)


.NOTES
Created:    2019-06-21
Version:    0.5 (Pre-release)

Update 21 June 2019
Creatied initial script, built out some basic functions but nothing is really called upon yet.
************************************************************************************************************************
#>
Param(
	[Parameter(Mandatory=$false, Position=0, HelpMessage="Type of server?")]
	[String]$ServerBuild
  )

function startup {
	#Gathering Data
	$strCurrentInfo = (Get-WmiObject Win32_ComputerSystem)
	$strCurrentCompName = $strCurrentInfo.Name
	$strCurrentDomain = $strCurrentInfo.domain
	$strNetAdapter = (get-netipaddress -AddressFamily IPv4 | where InterfaceAlias -like "*Ethernet*")
	$n = ($strNetAdapter | measure); if ($n.count -gt "1"){Write-Host -ForegroundColor Red "Multiple available network adapters present"}
	$strCurrentIP = $strNetAdapter.IPAddress
	if ($strNetAdapter.AddressState -eq "Prefered"){Write-Host -ForegroundColor red "Warning! Network adapter is currently set for DHCP"}
	$script:strInterfaceAlias = $strNetAdapter.InterfaceAlias

	#load switch options
	$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes","Description."
	$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No","Description."
	$cancel = New-Object System.Management.Automation.Host.ChoiceDescription "&Cancel","Description."
	$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no, $cancel)
	
	$title = "
	Current Config is:
	------------------
	Name: $strCurrentCompName
	IP: $strCurrentIP
	Doamin: $strCurrentDomain
	
	"
	$message = "Would you like to update?"
	$result = $host.ui.PromptForChoice($title, $message, $options, 1)
	switch ($result) {
		0{	#Gathering Options
			$strComputerName = read-host "Enter new Device Name"
			$strIpAddress = read-host "Enter new IP Address"
			$strDefaultGateWay = read-host "Enter new Default Gateway"
			$strDnsAddress = read-host "Enter new DNS Server"
			$strDomain = read-host "Enter target domain to join"
			#Options gathered, setting config
			if ($strComputerName) {rename-computer -NewName $strComputerName}
			if ($strIpAddress) {
				Set-TimeZone -Name "US Mountain Standard Time"
				New-NetIPAddress -InterfaceAlias $strInterfaceAlias -AddressFamily IPv4  -IPAddress $strIpAddress -PrefixLength 24 -DefaultGateway $strDefaultGateWay
				Set-DnsClientServerAddress -InterfaceAlias $strInterfaceAlias -ServerAddresses $strDnsAddress
				}
			if ($strDomain){add-computer –domainname $strDomain}
			}
		1{Write-Host "Not Changed"}
		2{Write-Host "Canceling..." ; exit}
	}
}

function setup-DomainController {

	#load switch options
	$NewForest = New-Object System.Management.Automation.Host.ChoiceDescription "&New","Description."
	$JoinForest = New-Object System.Management.Automation.Host.ChoiceDescription "&Join","Description."
	$cancel = New-Object System.Management.Automation.Host.ChoiceDescription "&Cancel","Description."
	$options = [System.Management.Automation.Host.ChoiceDescription[]]($NewForest, $JoinForest, $cancel)

	$title = "Setting up Domain Controller"
	$message = "Create new forest?	Joining existing Forest, Select 2"
	$result = $host.ui.PromptForChoice($title, $message, $options, 1)
	switch ($result) {
		0{	#New Forest
			Write-host -ForegroundColor Yellow "Creating a new Forest"
			Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
			Install-ADDSForest -DomainName $TargetDomain -InstallDNS:$True
		}
		1{	#Join Existing Forest
			Write-host -ForegroundColor Yellow "Joining an existing Forest"
			Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
			Install-ADDSDomainController -Domainname $TargetDomain -InstallDNS:$True -credential (Get-Credential)
		}
		2{Write-Host "Canceling..." ; exit}
	}
}

fucntion set-wsusconfig {
#	Installing and base configuration of WSUS
	Install-WindowsFeature -Name UpdateServices, UpdateServices-DB -IncludeManagementTools
	Remove-WindowsFeature -Name UpdateServices-WidDB
	$strSQLServer = read-host "SQL Server FQDN"
	$strWsusContentPath = read-host "Path to WSUS Content"
	if (!(test-path $strWsusContentPath)){New-Item -ItemType Directory $strWsusContentPath}
	$WsusUtil =  "C:\Program Files\Update Services\Tools\wsusutil.exe"
	& $WsusUtil postinstall CONTENT_DIR="$strWsusContentPath" SQL_Instance_Name="$strSQLServer"
	
	Write-Verbose "Get WSUS Server Object" -Verbose
	$wsus = Get-WSUSServer

	Write-Verbose "Connect to WSUS server configuration" -Verbose
	$wsusConfig = $wsus.GetConfiguration()

	Write-Verbose "Set to download updates from Microsoft Updates" -Verbose
	Set-WsusServerSynchronization -SyncFromMU

	Write-Verbose "Set Update Languages to English and save configuration settings" -Verbose
	$wsusConfig.AllUpdateLanguagesEnabled = $false           
	$wsusConfig.SetEnabledUpdateLanguages("en")           
	$wsusConfig.Save()

	Write-Verbose "Get WSUS Subscription and perform initial synchronization to get latest categories" -Verbose
	$subscription = $wsus.GetSubscription()
	$subscription.StartSynchronizationForCategoryOnly()

		While ($subscription.GetSynchronizationStatus() -ne 'NotProcessing') {
			Write-Host "." -NoNewline
			Start-Sleep -Seconds 5
		}

	Write-Verbose "Sync is Done" -Verbose

	Write-Verbose "Disable Products" -Verbose
	Get-WsusServer | Get-WsusProduct | Where-Object -FilterScript { $_.product.title -match "Office" } | Set-WsusProduct -Disable
	Get-WsusServer | Get-WsusProduct | Where-Object -FilterScript { $_.product.title -match "Windows" } | Set-WsusProduct -Disable
							
	Write-Verbose "Enable Products" -Verbose
	Get-WsusServer | Get-WsusProduct | Where-Object -FilterScript { $_.product.title -match "Windows Server 2016" } | Set-WsusProduct

	Write-Verbose "Disable Language Packs" -Verbose
	Get-WsusServer | Get-WsusProduct | Where-Object -FilterScript { $_.product.title -match "Language Packs" } | Set-WsusProduct -Disable

	Write-Verbose "Configure the Classifications" -Verbose

		Get-WsusClassification | Where-Object {
			$_.Classification.Title -in (
				'Critical Updates',
				'Definition Updates',
				'Feature Packs',
				'Security Updates',
				'Service Packs',
				'Update Rollups',
				'Updates')
			} | Set-WsusClassification

	Write-Verbose "Configure Synchronizations" -Verbose
	$subscription.SynchronizeAutomatically=$true

	Write-Verbose "Set synchronization scheduled for midnight each night" -Verbose
	$subscription.SynchronizeAutomaticallyTimeOfDay= (New-TimeSpan -Hours 0)
	$subscription.NumberOfSynchronizationsPerDay=1
	$subscription.Save()

	Write-Verbose "Kick Off Synchronization" -Verbose
	$subscription.StartSynchronization()

	Write-Verbose "Monitor Progress of Synchronisation" -Verbose

	Start-Sleep -Seconds 60 # Wait for sync to start before monitoring
		while ($subscription.GetSynchronizationProgress().ProcessedItems -ne $subscription.GetSynchronizationProgress().TotalItems) {
			#$subscription.GetSynchronizationProgress().ProcessedItems * 100/($subscription.GetSynchronizationProgress().TotalItems)
			Start-Sleep -Seconds 5
		}
}

#runs startup config
clear
startup