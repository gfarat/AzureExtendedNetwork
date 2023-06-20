
# --------------------------------------------------------------
#  Copyright © Microsoft Corporation.  All Rights Reserved.
#  Microsoft Corporation (or based on where you live, one of its affiliates) licenses this sample code for your internal testing purposes only.
#  Microsoft provides the following sample code AS IS without warranty of any kind. The sample code arenot supported under any Microsoft standard support program or services.
#  Microsoft further disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose.
#  The entire risk arising out of the use or performance of the sample code remains with you.
#  In no event shall Microsoft, its authors, or anyone else involved in the creation, production, or delivery of the code be liable for any damages whatsoever
#  (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss)
#  arising out of the use of or inability to use the sample code, even if Microsoft has been advised of the possibility of such damages.
# ---------------------------------------------------------------


function Get-ExtendedNetworkIPAddresses 
{
    [CmdletBinding()]

    $ComputerSystem = Get-CimInstance -Class Win32_ComputerSystem;
    $ComputerName = $ComputerSystem.DNSHostName
    if ($null -eq $ComputerName) {
        $ComputerName = $ComputerSystem.Name
    }
    $fqdn = ([System.Net.Dns]::GetHostByName($ComputerName)).HostName
    $uri = "https://" + $fqdn + "/extendednetwork/v1/config"

    $ExtNwAgentRegKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\ExtNwAgent\Parameters"
    $ClientCertProperty = "ClientCertificateSubjectName"
    $certSubject = Get-ItemPropertyValue -Path $ExtNwAgentRegKeyPath -Name $ClientCertProperty -ErrorAction SilentlyContinue
    $cert = Get-Item "Cert:\LocalMachine\my\*" | Where-Object {$_.Subject.ToUpper().StartsWith("CN=$certSubject".ToUpperInvariant())} | Where-Object { $_.FriendlyName -like "*azureExtendedNetwork*" } | Microsoft.PowerShell.Utility\Select-Object -Last 1


    $result = (Invoke-WebRequest -Uri $uri -Certificate $cert -UseBasicParsing).content

    write-verbose $result

    $psresult = $result | convertfrom-json 
    
    $ipaddresses = @()

    foreach ($ip in $psresult.extendednetwork.localipaddresses) {
        $newip = new-object -TypeName PSObject
        $newip | add-member -notepropertyname IPAddress -notepropertyvalue $ip.ipv4address
        $newip | add-member -notepropertyname Location -notepropertyvalue 'Local'
        $ipaddresses += $newip
    }
    foreach ($ip in $psresult.extendednetwork.remoteipaddresses) {
        $newip = new-object -TypeName PSObject
        $newip | add-member -notepropertyname IPAddress -notepropertyvalue $ip.ipv4address
        $newip | add-member -notepropertyname Location -notepropertyvalue 'Remote'
        $ipaddresses += $newip
    }

    return $ipaddresses

}

####################################
function Add-ExtendedNetworkIPAddress 
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [String] $IPAddress,
        [Parameter(Mandatory=$true)]
        [String] $Location
    )

    $ComputerSystem = Get-CimInstance -Class Win32_ComputerSystem;
    $ComputerName = $ComputerSystem.DNSHostName
    if ($null -eq $ComputerName) {
        $ComputerName = $ComputerSystem.Name
    }
    $fqdn = ([System.Net.Dns]::GetHostByName($ComputerName)).HostName
    $uri = "https://" + $fqdn + "/extendednetwork/v1/config"

    $ExtNwAgentRegKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\ExtNwAgent\Parameters"
    $ClientCertProperty = "ClientCertificateSubjectName"
    $certSubject = Get-ItemPropertyValue -Path $ExtNwAgentRegKeyPath -Name $ClientCertProperty -ErrorAction SilentlyContinue
    $cert = Get-Item "Cert:\LocalMachine\my\*" | Where-Object {$_.Subject.ToUpper().StartsWith("CN=$certSubject".ToUpperInvariant())} | Where-Object { $_.FriendlyName -like "*azureExtendedNetwork*" } | Microsoft.PowerShell.Utility\Select-Object -Last 1

    #Get old values
    $result = (Invoke-WebRequest -Uri $uri -Certificate $cert -UseBasicParsing).content
    $psresult = $result | convertfrom-json 
 
    #check to see if ip already exists
    foreach ($ip in $psresult.extendednetwork.localIPAddresses) {
        if ($ipaddress -eq $ip.ipv4address) {
            throw "IP address already exists in local list."
        }
    }
    foreach ($ip in $psresult.extendednetwork.remoteIPAddresses) {
        if ($ipaddress -eq $ip.ipv4address) {
            throw "IP address already exists in remote list."
        }
    }

    #update the list
    $newip = new-object -TypeName PSObject
    $newip | add-member -notepropertyname ipv4Address -notepropertyvalue $ipaddress
    
    if ($Location -eq "Local") {
        $psresult.extendednetwork.localIPAddresses += $newip
    } else {
        $psresult.extendednetwork.remoteIPAddresses += $newip
    }
    #put the updated list

    $headers = @{"Accept"="application/json"}
    $content = "application/json; charset=UTF-8"
    $timeout = 10
    $method = "Put"

    $uri = "https://" + $fqdn +"/extendednetwork/v1/config"  #Update the Uri
    $body = $psresult | convertto-json -depth 10

    $result = Invoke-WebRequest -Headers $headers -ContentType $content -Method $method -Uri $uri -Body $body -Certificate $cert -DisableKeepAlive -UseBasicParsing

    get-extendednetworkipaddresses
}


function Remove-ExtendedNetworkIPAddress 
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [String]
        $IPAddress
    )

    $ComputerSystem = Get-CimInstance -Class Win32_ComputerSystem;
    $ComputerName = $ComputerSystem.DNSHostName
    if ($null -eq $ComputerName) {
        $ComputerName = $ComputerSystem.Name
    }
    $fqdn = ([System.Net.Dns]::GetHostByName($ComputerName)).HostName
    $uri = "https://" + $fqdn + "/extendednetwork/v1/config"

    $ExtNwAgentRegKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\ExtNwAgent\Parameters"
    $ClientCertProperty = "ClientCertificateSubjectName"
    $certSubject = Get-ItemPropertyValue -Path $ExtNwAgentRegKeyPath -Name $ClientCertProperty -ErrorAction SilentlyContinue
    $cert = Get-Item "Cert:\LocalMachine\my\*" | Where-Object {$_.Subject.ToUpper().StartsWith("CN=$certSubject".ToUpperInvariant())} | Where-Object { $_.FriendlyName -like "*azureExtendedNetwork*" } | Microsoft.PowerShell.Utility\Select-Object -Last 1

    #Get old values
    $result = (Invoke-WebRequest -Uri $uri -Certificate $cert -UseBasicParsing).content
    $psresult = $result | convertfrom-json 
 
    #update the list
    $newlocal = @()

    foreach ($ip in $psresult.extendednetwork.localIPAddresses) {
        if ($ipaddress -ne $ip.ipv4address) {
            $newlocal += $ip
        }
    }
    $psresult.extendednetwork.localIPAddresses = $newlocal

    $newremote = @()

    foreach ($ip in $psresult.extendednetwork.remoteIPAddresses) {
        if ($ipaddress -ne $ip.ipv4address) {
            $newremote += $ip
        }
    }
    $psresult.extendednetwork.remoteIPAddresses = $newremote

    #put the updated list

    $headers = @{"Accept"="application/json"}
    $content = "application/json; charset=UTF-8"
    $timeout = 10
    $method = "Put"

    $uri = "https://" + $fqdn +"/extendednetwork/v1/config"  #Update the Uri
    $body = $psresult | convertto-json -depth 10

    $result = Invoke-WebRequest -Headers $headers -ContentType $content -Method $method -Uri $uri -Body $body -Certificate $cert -DisableKeepAlive -UseBasicParsing

    get-extendednetworkipaddresses
}

Export-ModuleMember -Function Get-ExtendedNetworkIPAddresses
Export-ModuleMember -Function Add-ExtendedNetworkIPAddress
Export-ModuleMember -Function Remove-ExtendedNetworkIPAddress 

