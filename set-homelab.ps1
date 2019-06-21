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
	if ($strNetAdapter.AddressState -ne "Static"){Write-Host -ForegroundColor red "Warning! Network adapter is currently set for DHCP"}
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
		0{
		$Script:strComputerName = read-host "Enter new Device Name"
		$Script:strIpAddress = read-host "Enter new IP Address"
		$Script:strDefaultGateWay = read-host "Enter new Default Gateway"
		$Script:strDnsAddress = read-host "Enter new DNS Server"
		$Script:strDomain = read-host "Enter target domain to join"
		set-ServerConfig
	}
		1{Write-Host "Not Changed"}
		2{Write-Host "Canceling..." ; exit}
	}
}

function set-ServerConfig {
	if ($Script:strComputerName) {rename-computer -ComputerName $strComputerName}
	if ($Script:strIpAddress) {
		Set-TimeZone -Name "US Mountain Standard Time"
		New-NetIPAddress -InterfaceAlias $script:strInterfaceAlias -AddressFamily IPv4  -IPAddress $Script:strIpAddress -PrefixLength 24 -DefaultGateway $Script:strDefaultGateWay
		Set-DnsClientServerAddress -InterfaceAlias $script:strInterfaceAlias -ServerAddresses $Script:strDnsAddress
		}
	if ($script:strDomain){add-computer –domainname $Script:strDomain}
		
	
}


function setup-DomainController {

	#load switch options
	$NewForest = New-Object System.Management.Automation.Host.ChoiceDescription "&New","Description."
	$JoinForest = New-Object System.Management.Automation.Host.ChoiceDescription "&Join","Description."
	$cancel = New-Object System.Management.Automation.Host.ChoiceDescription "&Cancel","Description."
	$options = [System.Management.Automation.Host.ChoiceDescription[]]($NewForest, $JoinForest, $cancel)

	$title = "Setting up Domain Controller"
	$message = "Creating new forest, select 1?	Joining existing Forest, Select 2"
	$result = $host.ui.PromptForChoice($title, $message, $options, 1)
	switch ($result) {
		0{
			#New Forest
			Write-host -ForegroundColor Yellow "Creating a new Forest"
		}
		1{
			#Join Existing Forest
			Write-host -ForegroundColor Yellow "Joining an existing Forest"
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