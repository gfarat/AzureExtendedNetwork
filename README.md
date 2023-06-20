# Azure Extended Network

## Extend your subnet to Azure

You can extend your on-premises subnets to Azure using a layer-3 overlay network based solution. Most solutions use an overlay technology such as VXLAN to extend the layer-2 network using an layer-3 overlay network. The following diagram shows a generalized solution. In this solution, the same subnet exists on both sides that is, Azure and on-premises.

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/30dd5b8d-ce45-4e12-8a39-b6f103e4f56a)

The IP addresses from the subnet are assigned to VMs on Azure and on-premises. Both Azure and on-premises have an NVA inserted in their networks. When a VM in Azure tries to talk to a VM in on-premises network, the Azure NVA captures the packet, encapsulates it, and sends it over VPN/Express Route to the on-premises network. The on-premises NVA receives the packet, decapsulates it and forwards it to the intended recipient in its network. The return traffic uses a similar path and logic.

In the above example, the Azure NVA and the on-premises NVA communicate and learn about IP addresses behind each other. More complex networks can also have a mapping service, which maintains the mapping between the NVAs and the IP addresses behind them. When an NVA receives a packet, it queries the mapping service to find out the address of the NVA that has the destination IP address behind it.

## Overview
Extended network for Azure enables you to stretch an on-premises subnet into Azure to let on-premises virtual machines keep their original on-premises private IP addresses when migrating to Azure.

The network is extended using a bidirectional VXLAN tunnel between two Windows Server 2019 or above VMs acting as virtual appliances, one running on-premises and the other running in Azure, each also connected to the subnet to be extended. Each subnet that you are going to extend requires one pair of appliances. Multiple subnets can be extended using multiple pairs.

>**Note** Extended network for Azure should only be used for machines that cannot have their IP address changed when migrating to Azure. It is always better to change the IP address and connect it to a subnet that wholly exists in Azure, if that is an option.

# Environment

## Azure Side

- Virtual network in Azure that contains at least two subnets
  - First CIDR for Routed Network must be unique within your routing domain so that it does not overlap with any on-premises subnets
  - Second CIDR as the on-premises subnet that you want to extend, in addition to subnets required for your gateway connection.
- Connection with On-Premises using Site-to-Site VPN or Express Route
- VM Windows Server 2022 **Azure Edition** that is capable of running nested virtualization with 2 NICs. This is the Azure virtual appliance.
  - Fist network interface connect to the routable subnet
  - Second network interface connect to the extended subnet

>**Note** Extended network for Azure requires Windows Server 2022 Azure Edition for the VM that is running in Azure.

## On-premises Side

- Make sure the subnets are available on the physical machine where you will deploy the on-premises VM (virtual appliance). This includes the subnet you want to extend and a second subnet that is unique and doesn't overlap with any subnets in the Azure virtual network.
- VM Windows Server 2019 or above on any hypervisor that supports nested virtualization with 2 NICs. This is the on-premises virtual appliance.
  - Fist network interface connect to the routable subnet
  - Second network interface connect to the extended subnet
- VM Windows Server 2019 of above to install Windows Admin Center
>**Note** The VM that has Windows Admin Center installed has the ability to manage multiple Appliances, if it is necessary to extend a second subnet that requires an extra pair of appliances, it is not necessary to deploy a new VM for Windows Admin Center function.

## Solution Considerations

- Routing will be asymmetric
- If you have a firewall between Azure and On-premises
  - Disable sequence number randomization
  - Enable TCP state bypass
  - Require UDP port 4789 open both directions
- MTU reduced due to VXLAN overhead
- Broadcasts aren’t going to broadcast (can’t bring your own DHCP, PXE, etc)
- The first three addresses are reserved in Azure subnets
- Azure Virtual Network Router requires the first address in the subnet
- A slight increase in Latency and throughput may be reduced to ~1Gbps
- One appliance pair required per subnet must always be running
- Azure nested virtualization support check sku sizes (https://learn.microsoft.com/en-us/azure/virtual-machines/sizes)
  
![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/46b4dcd2-528d-4ef5-9f0c-6ff7070b52d0)

- For Azure nested virtualization support the security type of VM need to be Standard
  
![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/9b19a8b2-43cb-425a-908b-532a536fefce)

# Installation Process

## Appliances

1. In the two VMs (Azure and On-Premises) responsible for the virtual appliance function, we need to install the Windows Hyper-V feature and create two external virtual switches in the VM and connect one to each of the network interfaces. 

2. Enable Hyper-V Role (Restart required):
```powershell
Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart
```

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/ab4dfe44-f206-4b64-b858-820dfaf8a2b7)

3. After restart create the two virtual switches on the VMs and connect each one to its respective network card:

>**Note** The NetAdapterName can change depending on the VM, it is always important to check before running this second script. In my example I have already renamed the network cards as Routed and VXLAN.

```powershell
New-VMSwitch -Name "External" -AllowManagementOS $true -NetAdapterName "Ethernet"
New-VMSwitch -Name "Extended" -AllowManagementOS $true -NetAdapterName "Ethernet 2"
```
![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/ac1fd092-72d4-4d13-9e66-96405de212d6)


4. Disable RSC (Restart required):
```powershell
disable-netadapterrsc -name *
get-vmswitch | set-vmswitch -EnableSoftwareRsc $false
Shutdown -r -f -t 00
```
![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/39fe0459-eb2f-4068-8a66-4b466218b5d2)


>**Note** The reason is that RSC for TCP flows occurs before VXLAN encapsulation. Once the packet is encapsulated the now UDP packet is too large to send and since it is no longer TCP it can’t be fragmented again. The result is that the packet gets dropped resulting in retransmits. This can occur many times, reducing throughput significantly.

5. Create Firewall a new firewall rule to block ICMP ipv4. This setting can be overridden by adding an ACL on the edge router responsible for VPN tunneling or Express Route.

```powershell
New-NetFirewallRule -DisplayName "Block ICMP" -Direction Inbound -Protocol ICMPv4 -Action Block
```
>**Note** There is a known issue where ICMP messages come back and cause the retry count to be exceeded too quickly. If you configure the Windows firewall to block ICMP on the appliance that is initiating the connection it will prevent this from occurring. The product team plan to fix this in the next update to the extension.

## Windows Admin Center

1. Download and install Windows Admin Center on the server designated for this role. This server cannot be the same used for appliance function.
https://learn.microsoft.com/en-us/windows-server/manage/windows-admin-center/overview

2. In Windows Admin Center, select Settings (from the upper-right corner of the page) > Extensions. Then select Extensions:

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/be6bcac3-a0e3-48e8-bce6-ed05a1e5a43c)


3. On the Available extensions tab, select Extended network, and then select Install. After a few seconds you should see a message indicating a successful installation.

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/10c8da63-c8ed-4360-a43b-b2caa39436df)

After a few seconds you should see a message indicating a successful installation.

4. Connect Windows Admin Center to Azure, if you haven’t already done so. If you skip this step now, we'll ask you to do so later in the process.

5. Register your Azure Account

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/330d0035-9be5-40e8-8d4c-8ebad5df57e4)

6. Copy the code and enter it on the login screen followed by your Azure login
   
![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/2f1497fb-9aa6-4169-818e-09688598d08b)

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/22c64287-1832-4c75-a94f-d0e9bd64ff94)

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/30e649f2-4d03-495b-bbef-011449a4914c)

7. Select the tenant that will register the Azure Application
   
![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/3b5a59eb-5f42-4f62-bc4b-6bf74fa86942)

>**Note** For App Registration the minimum permission required in Azure AD is Application Administrator.

8. Select in the upper left corner "All Connections", + Add and add the Onpremises server under "Servers"
   
![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/28fb9f67-a737-4f86-b248-21bfdedd2579)

9. Enter the IP address of the appliance server installed in the on-premises environment, and if it is outside the domain, enter the Appliance administration password for the Windows Admin Center connection.

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/edd079dd-f2fa-47b5-897d-63fdaed92145)

10. After adding the server connect to it via the Windows Admin Center

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/b5e6e50d-d4ec-4512-8606-d23353fd24ea)
    
12. Click on Extended network to begin. The first time you will be presented with an overview and a setup button

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/070fe014-2845-46d4-b7e0-6a4e0ce29051)

# Deploy Extended Network for Azure
 
1. Click Set up to begin the configuration.

2. Click Next to proceed past the Overview.

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/0a75fdbe-94cc-4265-bbc4-ad6d26a6c92c)

3. Select the Subnet CIDR of the on-premises network that you want to extend. The list of subnets is read in from the virtual appliance. If you have not connected the virtual appliance to the correct set of subnets, you will not see the desired subnet CIDR in this list.

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/4bf6b433-b386-4ba7-b919-d8f9be079dd1)

4. Select the subscription, resource Group and virtual network that you are extending into:

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/465cbba7-f577-40ad-b1ca-79f02a8c5c80)

The region (Azure location) and subnet are selected automatically. Select Next: Extended-Network Gateway Setup to proceed.

5. You will now configure the virtual appliances. The on-premises gateway should have its information populated automatically:

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/873ff81e-4632-4125-8940-eeaf3522e44f)

If it looks correct, you can click Next.

6. For the Azure virtual appliance you will need to select the resource group, VM to use and Azure Gateway subnet CIDR:

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/ac438ca7-773f-43b6-b2e9-eb9efa9a159e)

>**Note** The VM list for the Azure virtual appliance only includes Azure VMs that contain Windows Server 2022 Azure Edition. If you do not see your VM in the list, make sure it is the Azure Edition and re-create if it is not.

7. Review the summary information then click Deploy to begin the deployment process. Deployment will take approximately 5-10 minutes. 

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/4d1f719d-73d8-426c-9132-faef80219006)

8. When deployment is complete, you will see the following panel for managing the extended IP addresses, and the status should say OK

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/90a6af3f-d28d-4de3-8b33-21aa8f13f896)

9. After finishing the installation of the appliances apply the fix for the issues 2 and 3 on both sides.
<!-- TOC -->
[Know Issues](https://github.com/gfarat/AzureExtendedNetwork/tree/main#known-issues)
<!-- /TOC -->

# Manage

Each IP address that you want to be reachable across the extended network will need to be configured. You can configure up to 250 addresses to extend.

To extend an address

1. Click on "Add IPv4 Addresses"

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/041abc38-dada-4316-a67a-bac512d908ac)

2. You will see the Add new IPv4 Addresses flyout on the right:

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/5b0ba193-2fff-4b14-b8fe-0e007009f3ff)

3. Use the Add button to manually add an address. Addresses that you add that are on-premises will be reachable by the Azure Addresses that you add to the Azure Address list, and vice versa.
   
4. Extended network for Azure scans the network to discover IP addresses, and populates the Suggestion lists based on this scan. To extend these addresses, you must use the dropdown list and select the checkbox next to the discovered address. Not all addresses will be discovered. Optionally, use the Add button to manually add addresses that are not discovered automatically.

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/2b6c753f-c4f6-4517-8840-b943f8954bdb)

5. Click Submit when complete. You will see the status change to Updating, then Progressing, and finally back to OK when the configuration is complete.

Your addresses are now extended. Use the Add IPv4 Addresses button to add additional addresses at any time. If an IP address is no longer in use at either end of the extended network, select the checkbox next to it and select Remove IPv4 Addresses.

If you no longer want to use extended network for Azure, click the Remove Azure Extended-Network button. This will uninstall the agent from the two virtual appliances and remove the extended IP addresses. The network will stop being extended. You will have to re-run the setup after removing it, if you want to start using the extended network again.

# Known issues

We have three known issues related to the network extension process that have workarounds or fixes that can be applied, all of which will be fixed in the next release.

1. ICMP messages come back and cause the retry count to be exceeded too quickly.  If you configure the Windows firewall to block ICMP on the appliance that is initiating the connection it will prevent this from occurring.

>**NOTE** This workaround was mentioned in Installation Process, Appliances, item 5.

2. If you map more than approximately 10 ip addresses then Windows Admin Center will fail to apply the configuration and enter a persistent error state.

3. Traffic from outside of the extended subnet that tries to reach a VM within the subnet and across the extension will get dropped.  

## Workaround from issue 1

Create Firewall a new firewall rule to block ICMP ipv4. This setting can be overridden by adding an ACL on the edge router responsible for VPN tunneling or Express Route.

```powershell
New-NetFirewallRule -DisplayName "Block ICMP" -Direction Inbound -Protocol ICMPv4 -Action Block
```
## Workaround from issue 2

1. Copy the [ExtendedNetwork.psm1](https://github.com/gfarat/AzureExtendedNetwork/blob/main/ExtendedNetwork.psm1) file module to each appliance

2. Open Powershell on each, change to the directory where you placed the module and run the following command:

```powershell
Import-module .\ExtendedNetwork.psm1
```

It contains three cmdlets:

Get-extendednetworkipaddresses
Add-extendednetworkipaddress
Remove-extendednetworkipaddress

3. First verify that the cmdlets work by running the get cmdlet on each appliance (no parameters required.)  

```powershell
Get-ExtendedNetworkIPAddresses
```
You should see this output on each:

Azure appliance:

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/a7f8b256-b224-420b-bfc9-2464b4527305)

OnPrem appliance:

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/9965ebdd-1a50-43ef-b3d9-86b6cef6cb56)


>**NOTE** Each should always contain the exact set of IP addresses, but with local and remote swapped.

4. To add an ip address you will need to run the add cmdlet on each side, but with the Location swapped each time. You will specify local if the IP Address is located on the same half of the network where the appliance is.

For example if the VM is in Azure you will run the following on the Azure Appliance:

```powershell
Add-ExtendedNetworkIPAddress -ipaddress 192.168.2.11 -location local
```

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/16e5064c-c1a7-4993-b14d-60e3f07248cb)


You should verify that the IP address appears in the list.

Then, you will run the same command in the on-prem appliance, but this time specify remote (since the machine whose ip address you are extending is remote in Azure):

```powershell
Add-ExtendedNetworkIPAddress -ipaddress 192.168.2.11 -location Remote
```

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/cf052259-d3de-4ecd-9d22-a5c0fe6bc257)

If the VM is located in Azure as in the above example then you are done, the traffic should start working after several seconds.

If the VM is located on-prem (this is important) then you need to add an IP configuration for the IP address to the appliance in Azure.  You can do this through the portal in this way:

5. Navigate to the Appliance network interface that is connected to the extended subnet, then click on IP Configurations on the left 

6. Click Add to add the new IP address. 

7. Make sure the name is in the format “ipconfig-<ipaddress>” like you see below.  Allocation must be “Static” and public ip address is “Disassociate”.
   
![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/50c4cad3-5ee8-49af-aeea-4497dae6385d)

9. After adding the ip configuration then traffic should be able to reach the on-prem address.

>**IMPORTANT NOTE** At all times the ip address lists must stay in sync, with the only difference being that local and remote are swapped.

9. If you make a mistake you can remove the address with remove cmdlet

```powershell
Remove-ExtendedNetworkIPAddress -ipaddress 192.168.2.11
```

Make sure you do this on both appliances so they are in sync, and keep the ipconfiguration in Azure matching the addresses that are on-prem local.

>**IMPORTANT NOTE** Do not ever delete the Primary ip configuration from the appliance in Azure.

## Workaround from issue 3

You will need to run the following steps on both of the extended network appliances:

1.	Open a powershell window with Administrator privilege

2.	Run the command:

```powershell
stop-service extnwagent
```
>**NOTE** If you get an error when stopping the service, repeat the command again and it should succeed the second time.

3.	Replace “c:\program files\Azure Extended Network Agent\ExtendedNwAgent.exe” with the updated version located here: [ExtendedNwAgent.exe](https://github.com/gfarat/AzureExtendedNetwork/blob/main/ExtendedNwAgent.exe)

5.	Verify the file hash with the command:

```powershell
get-filehash “c:\program files\Azure Extended Network Agent\ExtendedNwAgent.exe”
```
File has should be: 63956514D1267EC629CB206077383126E3661BB5D2F8561538DF9BE9261356B1

3.	Run the command:

```powershell
start-service extnwagent
```
4.	Repeat these steps for the second extended network appliance.

5.	Verify that two VMs on the extended subnet are still able to communicate with each other across the appliances

6.	Verify that a machine outside of the extended subnet is able to communicate with each of the machines regardless of which side of the subnet they are connected to. 

>**NOTE** Even after applying the fix there are many reasons why this communication test can fail if routing is not configured correctly on the network


Reference:

https://learn.microsoft.com/en-us/azure/virtual-network/subnet-extension

https://learn.microsoft.com/en-us/windows-server/manage/windows-admin-center/azure/azure-extended-network

https://learn.microsoft.com/en-us/virtualization/hyper-v-on-windows/user-guide/nested-virtualization

https://www.hciharrison.com/azure-stack-hci/azure-extended-networks/
