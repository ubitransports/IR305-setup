function Error ($rc) {
    Write-Error "Error code $rc"
    Write-Error "Contact me at r.bauduin-ext@ubitransport.com or +33 6 68 36 05 72 if emergency"
    Write-Host ""
    Read-Host -Prompt "Press Enter to exit..."
    exit
}

# On vérifie que le routeur est accessible
Write-Host "Checking that the router is accessible ..."
$hostname = "192.168.2.1"
$maxTry = 5
$delay = 3

for ($i=0; $i -lt $maxTry; $i++) {
    $result = Test-Connection -ComputerName $hostname -Count 1 -Quiet -ErrorAction SilentlyContinue
    if ($result -eq $true) {
        Write-Output "The router is connected."
	break
    } else {
	    Write-Output "The router is not connected. Retry ... [$i/$maxTry]"
            Start-Sleep -Seconds $delay
	}
}

if($result -ne $true) {
	Write-Error "Unable to connect to the router [${hostname}]"
	Error 1
}


# Menu interactif pour choisir le client
Write-Host "Choose the client :"
Write-Host "1. TGL"
Write-Host "2. Annonay"
Write-Host "3. Region Sud"
Write-Host "4. YELO"
$choice = Read-Host -Prompt 'Type 1, 2, 3 or 4'

switch ($choice) {
    1 { $client = "TGL" }
    2 { $client = "Annonay" }
    3 { $client = "Region Sud" }
    4 { $client = "YELO" }
    default { Write-Host "Invalid choice";Read-Host -Prompt "Press Enter to exit..."; exit }
}

$payload = @{
    customer = $client
} | ConvertTo-Json

#Get the router serial
$serial = curl -s -S -u adm:123456 "${hostname}:4444/getinfo.cgi" -d "serials_number_info"
if ($serial -notmatch "serials_number=RF") {
	Write-Error "Error when trying to get router serial $serial"
	Error 2
}

if ($serial -match "serials_number=(\w+)") {
    $serial = $Matches[1]
} else {
	Write-Error "Error when trying to get router serial $serial"
	Error 3
}

Write-Output "Router serial : ${serial}"

# URL de l'API pour obtenir le fichier de configuration
$url = "https://api.bauduin.me/ubi/router/$serial/config"

# Télécharger le fichier de configuration
try {
    $response = Invoke-WebRequest -Uri $url -Method Post -Body $payload -ContentType "application/json" -OutFile "config_IR305.dat"
} catch {
    $StatusCode = [int]$_.Exception.Response.StatusCode

    if ($StatusCode -eq 404) {
        Write-Error "Not found!"
    } elseif ($StatusCode -eq 500) {
        Write-Error "InternalServerError: Something went wrong on the backend!"
    } elseif ($StatusCode -eq 400) {
        Write-Error "Bad Request: Verify if serial start by RF!"
    }
    else {
        Write-Error "Expected 200, got $([int]$StatusCode)"
    }
	Error 4
}

# URL pour télécharger le fichier de configuration sur le routeur
$urlUpload = "http://${hostname}:4444/upload.cgi?type=config"
$filePath = Get-Item "config_IR305.dat"

$Form = @{
    filename = Get-Content $filePath -Raw
}

try {
	Write-Host "Transfert du fichier de configuration sur le routeur en cours"
	$curlOutput = curl -s -S -u adm:123456 -F "filename=@config_IR305.dat" "$urlUpload"
} catch {
	Write-Host "Error when trying to import configuration file on router"
	Error 5
}

# Vérifier que le routeur a répondu avec SUCCESS
if ($curlOutput -match "SUCCESS") {
   	Write-Host "Configuration applied successfully!"
} else {
    	Write-Error "Failed to apply configuration: $curlOutput"
	Error 6
}

# URL pour redémarrer le routeur
$urlReboot = "http://${hostname}:4444/getinfo.cgi"

# Redémarrer le routeur
Write-Host "Rebooting the router ..."
$rebootOutput = curl -s -S -u adm:123456 -X POST "$urlReboot" -d "reboot"

# Pause pour permettre au routeur de commencer le redémarrage
Write-Host "Waiting for the router to be DOWN ..."

$maxTry = 12
$delay = 3 # Délai en secondes
$reboot = 0

for ($i=0; $i -lt $maxTry; $i++) {
    $result = Test-Connection -ComputerName $hostname -Count 1 -Quiet -ErrorAction SilentlyContinue
    if ($result -eq $true) {
        Write-Output "The router is online."
        Start-Sleep -Seconds $delay
    } else {
	Write-Output "The router is rebooting."
	$reboot = 1
	$hostname = "192.168.1.1"
        Start-Sleep -Seconds $delay
    }
}

if($reboot = 0) {
	Write-Error "The router did not reboot."
	Error 7
}
if($result -ne $true) {
	Write-Error "Router is down."
	Error 8
}


Write-Host "Checking that the configuration has been imported successfully..."
$wlanpwd = curl -s -S -u adm:123456 "${hostname}:4444/getinfo.cgi" -d "wl0_wpa_psk"

if ($wlanpwd -notmatch "wl0_wpa_psk=") {
	Write-Error "Error when trying to get router wlan password $wlanpwdl"
	Error 9
}

if ($wlanpwd -match "wl0_wpa_psk=(.+)") {
    $wlanpwd = $Matches[1]
} else {
	Write-Error "Error when trying to get router wlan password $wlanpwd"
	Error 10
}

$url = "https://api.bauduin.me/ubi/router/$serial/verify"

$payload = @{
    wlanpwd = $wlanpwd
} | ConvertTo-Json

try {
    $response = Invoke-WebRequest -Uri $url -Method Post -Body $payload -ContentType "application/json"
} catch {
    $StatusCode = [int]$_.Exception.Response.StatusCode

    if ($StatusCode -eq 404) {
        Write-Error "Not found!"
    } elseif ($StatusCode -eq 500) {
        Write-Error "InternalServerError: Something went wrong on the backend!"
    } elseif ($StatusCode -eq 400) {
        Write-Error "Bad Request: There was a problem when configuring the router"
    }
    else {
        Write-Error "Expected 200, got $([int]$StatusCode)"
    }
	Error 11
}

Write-Output "$serial has been successfully configured !"

Write-Output "Registering the router to the inhand MDM..."

$url = "https://api.bauduin.me/ubi/router/$serial/mdm"

try {
    $response = Invoke-WebRequest -Uri $url -Method Post -ContentType "application/json"
} catch {
    $StatusCode = [int]$_.Exception.Response.StatusCode

    if ($StatusCode -eq 404) {
        Write-Error "Not found!"
    } elseif ($StatusCode -eq 500) {
        Write-Error "InternalServerError: Something went wrong on the backend!"
    } elseif ($StatusCode -eq 400) {
        Write-Error "Bad Request: There was a problem when registering the router"
    }
    else {
        Write-Error "Expected 201, got $([int]$StatusCode)"
    }
	Error 12
}

if($StatusCode -eq 201) {
	Write-Ouput "$serial has been successfully added to MDM"
}
