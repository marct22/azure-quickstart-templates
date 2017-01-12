#Requires -Version 3.0
#Requires -Module AzureRM.Resources
#Requires -Module Azure.Storage
#Requires -Module AzureRM.Storage

# Remember, you can override these values by passing in -<parameter name> "value"
#                   ex. Deploy-AzureResourceGroup.ps1 -RemoveSpecificDeploy "<deploy name>"
# To see help, add in -Help as a parameter (order doesn't matter)
# 
# By default, ResourceGroupName = ArtifactStagingDirectory (minus .\ if you put it in), but you can
#                                 override it via -ResourceGroupName "alternatename"
#
# To see a list of the various azure Resource Group locations, run get-azureRmLocation, and use the value in 'Location :'
#
Param(
    [string] [Parameter(Mandatory=$true)] $ArtifactStagingDirectory,
    [string] [Parameter(Mandatory=$true)] $ResourceGroupLocation,
    [string] $ResourceGroupName = $ArtifactStagingDirectory.replace('.\',''), # Strip off the  '.\' if present
    [switch] $UploadArtifacts,
    [string] $StorageAccountName,
    [string] $StorageContainerName = $ResourceGroupName.ToLowerInvariant() + '-stageartifacts',
    [string] $TemplateFile = $ArtifactStagingDirectory + '\azuredeploy.json',
    [string] $TemplateParametersFile = $ArtifactStagingDirectory + '.\azuredeploy.parameters.json',
    [string] $DSCSourceFolder = $ArtifactStagingDirectory + '.\DSC',
    [switch] $ValidateOnly,
    [switch] $ListDeployments,
    [switch] $RemoveSpecificDeploy,
    [string] $DeployName,
    [switch] $DeleteEverything,
    [switch] $Help
#    [string] $DebugOptions = "None"
)

Import-Module Azure -ErrorAction SilentlyContinue


try {
    [Microsoft.Azure.Common.Authentication.AzureSession]::ClientFactory.AddUserAgent("VSAzureTools-$UI$($host.name)".replace(" ","_"), "AzureRMSamples")
} catch { }

Set-StrictMode -Version 3

if ($Help) {
    Write-Output "Help!" 
    Write-Output " "
    Write-Output "Note: ResourceGroupName is by default identical to ArtifactStagingDirectory, but you CAN overwrite it via"
    Write-Output "                          -ResourceGroupName `"<another name>`""
    Write-Output " "
    Write-Output "ArtifactStagingDirectory: This is just the subfolder you wish to deploy from, which contains the json files"
    Write-Output "                          and optional artifacts. REQUIRED"
    Write-Output "                          Ex. -ArtifactStagingDirectory .\iis-2vm-sql-1vm"
    Write-Output "ResourceGroupLocation:    This is the Azure Location (like westus for West US or northeurope location. REQUIRED"
    Write-Output "                          Ex. -ResourceGroupLocation `"westus`""
    Write-Output "ValidateOnly:             This validates the json template files are correct. That is all it does."
    Write-Output "                          Ex. -ValidateOnly"
    Write-Output "ListDeployments:          This lists specific deployments on a specific Azure Resource Group and their status"
    Write-Output "                          Ex. -ListDeployments"
    Write-Output "RemoveSpecificDeploy:     This removes a specific deploy attempt in a particular Azure resource group."
    Write-Output "                          you MUST pass in the Deployment Name (usuallly named azuredeploy-MMDD-HHMM)"
    Write-Output "                          Ex. -RemoveSpecificDeploy -DeployName `"<name of deploy>`""
    Write-Output "DeleteEverything:         This deletes the Azure Resource Group and all metadata on that Resource Group, "
    Write-Output "                          including VMs, Virtual networks, storage areas, load balancers, etc. It will"
    Write-Output "                          delete even running VMs!"
    Write-Output "                          Ex. -DeleteEverything"


    exit 1
}

Write-Output "INFO: This will use the azure resource group named $ResourceGroupName, creating it if it doesn't already exist"

$OptionalParameters = New-Object -TypeName Hashtable
<#
$v = (Get-Module -Name AzureRM.Resources).Version
If ($v.Major -eq 1 -and $v.Minor -eq 2){
    Write-Warning "DeploymentDebugLogLevel is not available in this version of Azure PowerShell"
}
else{
    $OptionalParameters.Add('DeploymentDebugLogLevel', $DebugOptions)
}
#>
# TemplateFile is the absolute path to azuredeploy.json
# TemplateParameters is absolute path to azuredeploy.parameters.json
$TemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $TemplateFile))
$TemplateParametersFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $TemplateParametersFile))


if ($UploadArtifacts) {
Write-Output "got uploadartifacts being non-zero $UploadArtifacts"

    # Convert relative paths to absolute paths if needed
    $ArtifactStagingDirectory = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $ArtifactStagingDirectory))
    $DSCSourceFolder = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $DSCSourceFolder))

    Set-Variable ArtifactsLocationName '_artifactsLocation' -Option ReadOnly -Force
    Set-Variable ArtifactsLocationSasTokenName '_artifactsLocationSasToken' -Option ReadOnly -Force
	Set-Variable ArtifactsLocationResourceIdName '_artifactsLocationResourceId' -Option ReadOnly -Force

    $TemplateFileContent = Get-Content $TemplateFile -Raw | ConvertFrom-Json
    $TemplateParametersFileContent = Get-Content $TemplateParametersFile -Raw | ConvertFrom-Json
    #$TemplateParametersFileContent = $TemplateFileContent | Get-Member -Type NoteProperty | Where-Object {$_.Name -eq "parameters"}
    if (Get-Member -InputObject $TemplateParametersFileContent -Name parameters) {
        $TemplateParameters= $TemplateParametersFileContent.parameters
    }
    else {
        $TemplateParameters = $TemplateParametersFileContent
    }

    # Create a storage account name if none was provided
    if($StorageAccountName -eq "") {
        $subscriptionId = ((Get-AzureRmContext).Subscription.SubscriptionId).Replace('-', '').substring(0, 19)
        $StorageAccountName = "stage$subscriptionId"
    }

    $StorageAccount = (Get-AzureRmStorageAccount | Where-Object{$_.StorageAccountName -eq $StorageAccountName})

    # Create the storage account if it doesn't already exist
    if($StorageAccount -eq $null){
        $StorageResourceGroupName = "ARM_Deploy_Staging"
        New-AzureRmResourceGroup -Location "$ResourceGroupLocation" -Name $StorageResourceGroupName -Force
        $StorageAccount = New-AzureRmStorageAccount -StorageAccountName $StorageAccountName -Type 'Standard_LRS' -ResourceGroupName $StorageResourceGroupName -Location "$ResourceGroupLocation"
    }

    $StorageAccountContext = $storageAccount.Context
    
    if (Get-Member -InputObject $TemplateFileContent.parameters -Name _artifactsLocation) {
        if (Get-Member -InputObject $TemplateParameters -Name _artifactsLocation) {
            $OptionalParameters.Add($ArtifactsLocationName, $TemplateParameters._artifactsLocation.value)
        }                
        else {
            $OptionalParameters.Add($ArtifactsLocationName, $StorageAccountContext.BlobEndPoint + $StorageContainerName)
        }
    }

    if (Get-Member -InputObject $TemplateFileContent.parameters -Name _artifactsLocationResourceId) {
        if (Get-Member -InputObject $TemplateParameters -Name _artifactsLocationResourceId) {
            $OptionalParameters.Add($artifactsLocationResourceIdName, $TemplateParameters._artifactsLocationResourceId.value)
        }
        else {
            $OptionalParameters.Add($artifactsLocationResourceIdName, $storageAccount.Id)
        }
    }
    
    # Create DSC configuration archive
    if (Test-Path $DSCSourceFolder) {
        $DSCFiles = Get-ChildItem $DSCSourceFolder -File -Filter "*.ps1" | ForEach-Object -Process {$_.FullName}
        foreach ($DSCFile in $DSCFiles) {
            $DSCZipFile = $DSCFile.Replace(".ps1",".zip")
            Publish-AzureVMDscConfiguration -ConfigurationPath $DSCFile -ConfigurationArchivePath $DSCZipFile -Force
        }
    }

    # Copy files from the local storage staging location to the storage account container
    New-AzureStorageContainer -Name $StorageContainerName -Context $StorageAccountContext -Permission Container -ErrorAction SilentlyContinue *>&1
    
    $ArtifactFilePaths = Get-ChildItem $ArtifactStagingDirectory -Recurse -File | ForEach-Object -Process {$_.FullName}
    foreach ($SourcePath in $ArtifactFilePaths) {
        $BlobName = $SourcePath.Substring($ArtifactStagingDirectory.length + 1)
        Set-AzureStorageBlobContent -File $SourcePath -Blob $BlobName -Container $StorageContainerName -Context $StorageAccountContext -Force
    }

    # Generate the value for artifacts location SAS token if it is not provided in the parameter file
    if (Get-Member -InputObject $TemplateFileContent.parameters -Name _artifactsLocationSasToken) {
        if (Get-Member -InputObject $TemplateParameters -Name _artifactsLocationSasToken) {
            $OptionalParameters.Add($ArtifactsLocationSasTokenName, $TemplateParameters._artifactsLocationSasToken.value)
        }
        else {
            $ArtifactsLocationSasToken = New-AzureStorageContainerSASToken -Container $StorageContainerName -Context $StorageAccountContext -Permission r -ExpiryTime (Get-Date).AddHours(4)
            $ArtifactsLocationSasToken = ConvertTo-SecureString $ArtifactsLocationSasToken -AsPlainText -Force
            $OptionalParameters.Add($ArtifactsLocationSasTokenName, $ArtifactsLocationSasToken)
        }  
    }
}

# Create or update the resource group using the specified template file and template parameters file
# INFO: resource group is going to be named the folder you passed in in ArtifactStagingDirectory unless you
#       manually overrode it by using -ResourceGrupName "<different name>"
New-AzureRmResourceGroup -Name $ResourceGroupName -Location $ResourceGroupLocation -Verbose -Force -ErrorAction Stop 

if ($ValidateOnly) {
    # this only validates that the template is good.
    Test-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
                                        -TemplateFile $TemplateFile `
                                        -TemplateParameterFile $TemplateParametersFile `
                                        @OptionalParameters `
                                        -Verbose
} elseif ($ListDeployments) {
    Write-Output "Listing the Deloyments in Resource group ${ResourceGroupName}."
    Write-Output "If you want to remove a specific deployment, you can run "
    Write-Output "  Deploy-AzureResourceGroup.ps1 -ResourceGroupLocation $ResourceGroupLocation -ArtifactStagingDirectory $ArtifactStagingDirectory -RemoveSpecificDeploy -DeployName <name of deploy>"
    Get-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroupName 
                                           
} elseif ($RemoveSpecificDeploy) {
    Write-Output "This will remove the specific $RemoveSpecificDeploymentName deployment in Resource group ${ResourceGroupName}."
    Write-Output "To see a list of the deployments, run Deploy-AzureResourceGroup.pl1 -ResourceGroupLocation $ResourceGroupLocation -ArtifactStagingDirectory $ArtifactStagingDirectory -ListDeployments"
    Write-Output "or in Azure, in the specific Resource Group, click on "Deployments" and you can see the list of deployments"
    Remove-AzureRmResourceGroupDeployment -Name $DeployName `
                                          -ResourceGroupName $ResourceGroupName `
                                          -Confirm 
} elseif ($DeleteEverything) {
    Write-Output "This will remove the specific Azure Resource Group $ResourceGroupName, which deletes everything created on it,"
    Write-Output "such as virtual networks, VMs (even if running), storage areas, network configurations, load balancers, etc. "
    Write-Output "A handy way to delete entire environments and all it's associated metadata."
    
    Remove-AzureRmResourceGroup -ResourceGroupName $ResourceGroupName `
                                          -Confirm                                            
} else {
    Write-Output "This will now create (if necessary) the various azure items as specified in $TemplateFile"
    
    New-AzureRmResourceGroupDeployment -Name ((Get-ChildItem $TemplateFile).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
                                       -ResourceGroupName $ResourceGroupName `
                                       -TemplateFile $TemplateFile `
                                       -TemplateParameterFile $TemplateParametersFile `
                                       @OptionalParameters `
                                       -Force -Verbose 
}
