$strPath = "C:\Program Files (x86)\Common Files\Adobe\OOBE_Enterprise\RemoteUpdateManager\RemoteUpdateManager.exe"
$strArgs = "--action=install"
if (Test-Path $strPath){& $strPath $strArgs}