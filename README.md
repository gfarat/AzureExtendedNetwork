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

# Installation Process

## Appliances

In the two VMs (Azure and On-Premises) responsible for the virtual appliance function, we need to install the Windows Hyper-V feature and create two external virtual switches in the VM and connect one to each of the network interfaces. 

Enable Hyper-V Role (Restart required):
```powershell
Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart
```

After restart create the two virtual switches on the VMs and connect each one to its respective network card:
```powershell
New-VMSwitch -Name "External" -AllowManagementOS $true -NetAdapterName "Ethernet"
New-VMSwitch -Name "Extended" -AllowManagementOS $true -NetAdapterName "Ethernet 2"
```

Disable RSC (Restart required):
```powershell
disable-netadapterrsc -name *
get-vmswitch | set-vmswitch -EnableSoftwareRsc $false
Shutdown -r -f -t 00
```

>**Note** The reason is that RSC for TCP flows occurs before VXLAN encapsulation. Once the packet is encapsulated the now UDP packet is too large to send and since it is no longer TCP it can’t be fragmented again. The result is that the packet gets dropped resulting in retransmits. This can occur many times, reducing throughput significantly.

Create Firewall a new firewall rule to block ICMP ipv4 and disable ICMP ipv6

```powershell
New-NetFirewallRule -DisplayName "Block ICMP" -Direction Inbound -Protocol ICMPv4 -Action Block
Set-NetFirewallProfile -Profile Domain,Public,Private -Icmpv6InboundEchoRequest Blocked
Set-NetFirewallProfile -Profile Domain,Public,Private -Icmpv6OutboundDestinationUnreachable Blocked
```
>**Note** There is a known issue where ICMP messages come back and cause the retry count to be exceeded too quickly. If you configure the Windows firewall to block ICMP on the appliance that is initiating the connection it will prevent this from occurring. The product team plan to fix this in the next update to the extension.

## Windows Admin Center

Download and install Windows Admin Center onto any computer capable of running Windows Admin Center, other than the two virtual appliances you created earlier.
[https://learn.microsoft.com/en-us/windows-server/manage/windows-admin-center/overview](https://www.microsoft.com/en-us/evalcenter/download-windows-admin-center)
















**Install Process**
 
**##Install Hyper-V on agent Machines**

Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart

**##Configure Switch Virtual**

New-VMSwitch -Name "External" -AllowManagementOS $true -NetAdapterName "Ethernet"

New-VMSwitch -Name "Extended" -AllowManagementOS $true -NetAdapterName "Ethernet 2"

**Issue 1#**

There is a known issue where ICMP messages come back and cause the retry count to be exceeded too quickly.  If you configure the Windows firewall to block ICMP on the appliance that is initiating the connection it will prevent this from occurring.  We plan to fix this in the next update to the extension.

**Workaround Issue 1#**

##Create a new firewall rule to block ICMP ipv4 and disable ICMP ipv6

New-NetFirewallRule -DisplayName "Block ICMP" -Direction Inbound -Protocol ICMPv4 -Action Block

Set-NetFirewallProfile -Profile Domain,Public,Private -Icmpv6InboundEchoRequest Blocked

Set-NetFirewallProfile -Profile Domain,Public,Private -Icmpv6OutboundDestinationUnreachable Blocked

There is a known issue where ICMP messages come back and cause the retry count to be exceeded too quickly.  If you configure the Windows firewall to block ICMP on the appliance that is initiating the connection it will prevent this from occurring.  We plan to fix this in the next update to the extension.

##Disable RSC on agent machines (Need Restart VM)

disable-netadapterrsc -name *

get-vmswitch | set-vmswitch -EnableSoftwareRsc $false

Shutdown -r -f  -t 00

If you are seeing very poor performance (<1 Mbps) through the appliances for TCP traffic be sure to disable RSC on each appliance:

The reason is that RSC for TCP flows occurs before VXLAN encapsulation.  Once the packet is encapsulated the now UDP packet is too large to send and since it is no longer TCP it can’t be fragmented again.  The result is that the packet gets dropped resulting in retransmits.  This can occur many times, reducing throughput significantly.

**Issue 2#**

Traffic from outside of the extended subnet that tries to reach a VM within the subnet and across the extension will get dropped.  The issue is understood and a fix is in progress (I should have an ETA for you tomorrow).  Unfortunately there is no workaround.

**Workaround Issue 2#**

You will need to run the following steps on both of the extended network appliances:
Open a powershell window with Administrator privilege
Run:

stop-service extnwagent

If you get an error when stopping the service, repeat the command again and it should succeed the second time.
Replace “c:\program files\Azure Extended Network Agent\ExtendedNwAgent.exe” with the updated version

Verify the file hash with:

get-filehash “c:\program files\Azure Extended Network Agent\ExtendedNwAgent.exe”

File has should be: 63956514D1267EC629CB206077383126E3661BB5D2F8561538DF9BE9261356B1

Run:

Start-service extnwagent

Repeat these steps for the 2nd extended network appliance.
Verify that two VMs on the extended subnet are still able to communicate with each other across the appliances
Verify that a machine outside of the extended subnet is able to communicate with each of the machines regardless of which side of the subnet they are connected to.

**Issue 3#**

If you map more than approximately 10 ip addresses then Windows Admin Center will fail to apply the configuration and enter a persistent error state.   I have a poweshell module that will enable you to map the IP addresses through cmdlets that will enable you to work around this issue if you run into it.

**Workaround Issue 3#**

Copy the .psm1 file to each of each agent machines 

Open Powershell on each, change to the directory where you placed the module and run the following command:

Import-module .\ExtendedNetwork.psm1

It contains three cmdlets:

Get-extendednetworkipaddresses

Add-extendednetworkipaddress

Remove-extendednetworkipaddress

First verify that the cmdlets work by running get-extendednetworkipaddresses on each appliance (no parameters required.)     

You should see this output on each:

Azure appliance:

PS C:\> Get-ExtendedNetworkIPAddresses

 

IPAddress  Location

---------  --------

10.1.2.11  Local

10.1.2.100 Local

10.1.2.101 Local

10.1.2.10  Remote

10.1.2.200 Remote

 

OnPrem appliance:

PS C:\Program Files> get-extendednetworkipaddresses

 

IPAddress  Location

---------  --------

10.1.2.10  Local

10.1.2.200 Local

10.1.2.11  Remote

10.1.2.100 Remote

10.1.2.101 Remote

Notice they each should always contain the exact set of IP addresses, but with local and remote swapped.

To add an ip address you will need to run the add-extendednetworkipaddress cmdlet on each side, but with the Location swapped each time.  You will specify local if the Ip address is located on the same half of the network where the appliance is.  For example if the VM is in Azure you will run the following on the Azure Appliance:

 

PS C:\> add-extendednetworkipaddress -ipaddress 10.1.2.102 -location local

 

IPAddress  Location

---------  --------

10.1.2.11  Local

10.1.2.100 Local

10.1.2.101 Local

10.1.2.102 Local

10.1.2.10  Remote

10.1.2.200 Remote

 

You should verify that the IP address appears in the list.

 

Then, you will run the same command in the on-prem appliance, but this time specify remote (since the machine whose ip address you are extending is remote in Azure):

PS C:\> add-extendednetworkipaddress -ipaddress 10.1.2.102 -location Remote

IPAddress  Location

---------  --------

10.1.2.10  Local

10.1.2.200 Local

10.1.2.11  Remote

10.1.2.100 Remote

10.1.2.101 Remote

10.1.2.102 Remote

If the VM is located in Azure as in the above example then you are done, the traffic should start working after several seconds.

If the VM is located on-prem (this is important) then you need to add an IP configuration for the IP address to the appliance in Azure.  You can do this through the Powershell command line:



If you make a mistake you can remove the address with remove-extendednetworkipaddress:

PS C:\> Remove-ExtendedNetworkIPAddress -IPAddress 10.1.2.102

IPAddress  Location

---------  --------

10.1.2.11  Local

10.1.2.100 Local

10.1.2.101 Local

10.1.2.10  Remote

10.1.2.200 Remote

Make sure you do this on both appliances so they are in sync, and keep the ipconfiguration in Azure matching the addresses that are on-prem local.  If at any time you are not sure you can run get-extendednetworkipaddresses.

IMPORTANT: Do not ever delete the Primary ip configuration from the appliance in Azure.


**Solution considerations**

* Routing will be asymmetric
* If you have a firewall between Azure and On-premises
* Disable sequence number randomization
* Enable TCP state bypass
* Require UDP port 4789 open both directions

**MTU reduced due to VXLAN overhead

* Broadcasts aren’t going to broadcast (can’t bring your own DHCP, PXE, etc)
* The first three addresses are reserved in Azure subnets
* Azure Virtual Network Router requires the first address in the subnet
* A slight increase in Latency and throughput may be reduced to ~1Gbps
* One appliance pair required per subnet must always be running

Reference:

https://learn.microsoft.com/en-us/azure/virtual-network/subnet-extension

https://learn.microsoft.com/en-us/windows-server/manage/windows-admin-center/azure/azure-extended-network

https://learn.microsoft.com/en-us/virtualization/hyper-v-on-windows/user-guide/nested-virtualization

https://www.hciharrison.com/azure-stack-hci/azure-extended-networks/
