# AzureExtendedNetwork

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
* Additional steps may be required if using some form of SDN on-prem

Reference:
https://learn.microsoft.com/en-us/azure/virtual-network/subnet-extension
https://learn.microsoft.com/en-us/windows-server/manage/windows-admin-center/azure/azure-extended-network
https://learn.microsoft.com/en-us/virtualization/hyper-v-on-windows/user-guide/nested-virtualization
https://www.hciharrison.com/azure-stack-hci/azure-extended-networks/
