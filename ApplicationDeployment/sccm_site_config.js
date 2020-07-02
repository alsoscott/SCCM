$jsonParams = @"
{
     "$env:TEMP": "$Script:strTempDirectory",
      "\\server\share": "$Script:strFinalDirectory",
      "SMSSiteCode": "$Script:strSiteCode"
      "SCCM Site Server" : "$Script:strProviderMachineName"
   }
"@
