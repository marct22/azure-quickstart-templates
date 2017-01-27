# Production-like. creates 1-2 IIS web servers, 1-2 db servers, 1 util server, including installing IIS and SQL Server 2012. It does it all on a single 
# Azure resource group. Does NOT join any domains (uses workgroup, so you log in via workgroup\username), set in azuredeploy.parameters.json
# It pre-pends envPrefixName to all azure metadata (storage accounts, virtual networks, etc.).

# you can delete it all via 
# Deploy-AzureResourceGroup.ps1 -ResourceGroupLocation "<location like westus or northeurope>" -ArtifactStagingDirectory "prod-like" -DeleteEverything  (optional:
#         add -ResourceGroupName "<name of resource group>" if resource group name isn't 'prod-like')

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fazure%2Fazure-quickstart-templates%2Fmaster%2Fiis-2vm-sql-1vm%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png" />
</a>
<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2Fazure-quickstart-templates%2Fmaster%2Fiis-2vm-sql-1vm%2Fazuredeploy.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>
This template creates one or two Windows Server 2012R2 VM(s) with IIS configured using DSC. It also installs one or two SQL Server 2012 standard edition VM, 
a util server, a VNET with two subnets, NSG, load balancer, NATing and probing rules.

## Resources
The following resources are created by this template:
- 1 or 2 Windows 2012R2 IIS Web Servers.
- 1 or 2 SQL Server 2012 running on premium or standard storage.
- 1 Windows 2012R2 util server
- 1 virtual network with 2 subnets with NSG rules.
- 1 storage account for the VHD files.
- 1 Availability Set for IIS servers.
- 1 Load balancer with NATing rules.

If you want to override the environment prefix (currently met1), just modify azuredeploy.parameters.json

<img src="https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/iis-2vm-sql-1vm/images/resources.png" />


## Architecture Diagram
<img src="https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/iis-2vm-sql-1vm/images/architecture.png" />

