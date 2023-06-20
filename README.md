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

In the two VMs (Azure and On-Premises) responsible for the virtual appliance function, we need to install the Windows Hyper-V feature and create two external virtual switches in the VM and connect one to each of the network interfaces. 

Enable Hyper-V Role (Restart required):
```powershell
Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart
```

![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/ab4dfe44-f206-4b64-b858-820dfaf8a2b7)

After restart create the two virtual switches on the VMs and connect each one to its respective network card:
>**Note** The NetAdapterName can change depending on the VM, it is always important to check before running this second script. In my example I have already renamed the network cards as Routed and VXLAN.
```powershell
New-VMSwitch -Name "External" -AllowManagementOS $true -NetAdapterName "Ethernet"
New-VMSwitch -Name "Extended" -AllowManagementOS $true -NetAdapterName "Ethernet 2"
```
![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/ac1fd092-72d4-4d13-9e66-96405de212d6)


Disable RSC (Restart required):
```powershell
disable-netadapterrsc -name *
get-vmswitch | set-vmswitch -EnableSoftwareRsc $false
Shutdown -r -f -t 00
```
![image](https://github.com/gfarat/AzureExtendedNetwork/assets/55545933/39fe0459-eb2f-4068-8a66-4b466218b5d2)


>**Note** The reason is that RSC for TCP flows occurs before VXLAN encapsulation. Once the packet is encapsulated the now UDP packet is too large to send and since it is no longer TCP it can’t be fragmented again. The result is that the packet gets dropped resulting in retransmits. This can occur many times, reducing throughput significantly.

Create Firewall a new firewall rule to block ICMP ipv4. This setting can be overridden by adding an ACL on the edge router responsible for VPN tunneling or Express Route.

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



Reference:

https://learn.microsoft.com/en-us/azure/virtual-network/subnet-extension

https://learn.microsoft.com/en-us/windows-server/manage/windows-admin-center/azure/azure-extended-network

https://learn.microsoft.com/en-us/virtualization/hyper-v-on-windows/user-guide/nested-virtualization

https://www.hciharrison.com/azure-stack-hci/azure-extended-networks/
