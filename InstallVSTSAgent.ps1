# Downloads the Visual Studio Team Services Build Agent and installs on the new machine
# and registers with the Visual Studio Team Services account and build agent pool

# Enable -Verbose option
[CmdletBinding()]
Param(
[Parameter(Mandatory=$true)]$VSTSAccount = "daimler",
[Parameter(Mandatory=$true)]$PersonalAccessToken,
[Parameter(Mandatory=$true)]$AgentName,
[Parameter(Mandatory=$true)]$PoolName = "Core Windows"
)

$ErrorActionPreference = "Stop"

##
## Install VSTS Agent
##

Write-Verbose "Entering InstallVSTSAgent.ps1" -verbose

$currentLocation = Split-Path -parent $MyInvocation.MyCommand.Definition
Write-Verbose "Current folder: $currentLocation" -verbose

#Create a temporary directory where to download from VSTS the agent package (vsts-agent.zip) and then launch the configuration.
$agentTempFolderName = Join-Path $env:temp ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $agentTempFolderName
Write-Verbose "Temporary Agent download folder: $agentTempFolderName" -verbose

$serverUrl = "https://$VSTSAccount.visualstudio.com"
Write-Verbose "Server URL: $serverUrl" -verbose

$retryCount = 3
$retries = 1
Write-Verbose "Downloading Agent install files" -verbose
do
{
  try
  {
    Write-Verbose "Trying to get download URL for latest VSTS agent release..."
    $latestReleaseDownloadUrl = "https://vstsagentpackage.azureedge.net/agent/2.127.0/vsts-agent-win-x64-2.127.0.zip"
    Invoke-WebRequest -Uri $latestReleaseDownloadUrl -Method Get -OutFile "$agentTempFolderName\agent.zip"
    Write-Verbose "Downloaded agent successfully on attempt $retries" -verbose
    break
  }
  catch
  {
    $exceptionText = ($_ | Out-String).Trim()
    Write-Verbose "Exception occured downloading agent: $exceptionText in try number $retries" -verbose
    $retries++
    Start-Sleep -Seconds 30 
  }
} 
while ($retries -le $retryCount)

# Construct the agent folder under the main (hardcoded) C: drive.
$agentInstallationPath = Join-Path "C:" $AgentName 
# Create the directory for this agent.
New-Item -ItemType Directory -Force -Path $agentInstallationPath 

# Create a folder for the build work
$WorkFolder = "_work"
New-Item -ItemType Directory -Force -Path (Join-Path $agentInstallationPath $WorkFolder)


Write-Verbose "Extracting the zip file for the agent" -verbose
$destShellFolder = (new-object -com shell.application).namespace("$agentInstallationPath")
$destShellFolder.CopyHere((new-object -com shell.application).namespace("$agentTempFolderName\agent.zip").Items(),16)

# Removing the ZoneIdentifier from files downloaded from the internet so the plugins can be loaded
# Don't recurse down _work or _diag, those files are not blocked and cause the process to take much longer
Write-Verbose "Unblocking files" -verbose
Get-ChildItem -Recurse -Path $agentInstallationPath | Unblock-File | out-null

# Retrieve the path to the config.cmd file.
$agentConfigPath = [System.IO.Path]::Combine($agentInstallationPath, 'config.cmd')
Write-Verbose "Agent Location = $agentConfigPath" -Verbose
if (![System.IO.File]::Exists($agentConfigPath))
{
    Write-Error "File not found: $agentConfigPath" -Verbose
    return
}

# Call the agent with the configure command and all the options (this creates the settings file) without prompting
# the user or blocking the cmd execution

Write-Verbose "Configuring agent" -Verbose

# Set the current directory to the agent dedicated one previously created.
Push-Location -Path $agentInstallationPath

.\config.cmd --unattended --url $serverUrl --auth PAT --token $PersonalAccessToken --pool $PoolName --agent $AgentName --runasservice

Pop-Location

Write-Verbose "Agent install output: $LASTEXITCODE" -Verbose

Write-Verbose "Exiting InstallVSTSAgent.ps1" -Verbose


##
## Install Module AzurePS
##

Write-Verbose "Installing Module AzureRM..." -verbose

Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
Install-Module AzureRM

Write-Verbose "Finished installing Module AzureRM." -Verbose


##
## Install Azure CLI (latest)
## 
Write-Verbose "Installing Azure CLI ..." -verbose

$retryCount = 3
$retries = 1
Write-Verbose "Downloading Azure CLI .msi file" -verbose
$azureCliLocation = "$agentTempFolderName\azure-cli-latest.msi"
do
{
  try
  {
    Write-Verbose "Trying to get download URL for latest Azure CLI release..."
    $latestReleaseDownloadUrl = "https://azurecliprod.blob.core.windows.net/msi/azure-cli-latest.msi"
    Invoke-WebRequest -Uri $latestReleaseDownloadUrl -Method Get -OutFile $azureCliLocation
    Write-Verbose "Downloaded Azure CLI successfully on attempt $retries" -verbose
		
	$product= [WMICLASS]"\\.\ROOT\CIMV2:win32_Product"
	$product.Install($azureCliLocation)
    
	break
  }
  catch
  {
    $exceptionText = ($_ | Out-String).Trim()
    Write-Verbose "Exception occured downloading Azure CLI: $exceptionText in try number $retries" -verbose
    $retries++
    Start-Sleep -Seconds 30 
  }
} 
while ($retries -le $retryCount)


Write-Verbose "Restarting virtual machine to apply latest changes." -Verbose
Restart-Computer
