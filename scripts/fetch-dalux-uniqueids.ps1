# ==============================================================
# Dalux UniqueID Fetcher v2
# Haalt uniqueIDs, ExternalIDs en IfcGUIDs op via de Dalux API
# ==============================================================

# --- CONFIGURATIE ---
$auth = "422080:9gnoZYgsND74LD4h"
$siteRightsID = 563307
$contextHandle = "b1646911tDEFAULT"
$versionHash = 281617172
$projectID = "303048207527575552"
$callingUrl = "https://node2.build.dalux.com/client/$projectID/location/default"
$apiUrl = "https://node2.field.dalux.com/service-1-18/EntryPoints/Web/BimProxy.aspx/Web/ElementPropertiesGetUI3"

# --- BESTANDEN ---
$inputFile = "$PSScriptRoot\..\img\mids_lijst.txt"
$outputFile = "$PSScriptRoot\..\dalux_elements.csv"

# --- LEES MIDS ---
Write-Host "Mids inlezen uit $inputFile ..." -ForegroundColor Cyan
$lines = Get-Content $inputFile -Encoding UTF8 | Where-Object { $_ -match '^\d+\|' }
$elements = @()
foreach ($line in $lines) {
    $parts = $line.Split('|')
    if ($parts.Count -ge 3 -and $parts[0] -match '^\d+$') {
        $elements += [PSCustomObject]@{
            mid  = [int]$parts[0]
            eid  = $parts[1]
            name = $parts[2]
        }
    }
}
Write-Host "Totaal elementen gevonden: $($elements.Count)" -ForegroundColor Green

# --- UNIEKE MIDS ---
$uniqueMids = $elements | Select-Object -ExpandProperty mid -Unique | Sort-Object
Write-Host "Unieke mids: $($uniqueMids.Count)" -ForegroundColor Green

# --- BATCHES ---
$batchSize = 50
$batches = [System.Collections.ArrayList]@()
for ($i = 0; $i -lt $uniqueMids.Count; $i += $batchSize) {
    $batch = $uniqueMids[$i..([Math]::Min($i + $batchSize - 1, $uniqueMids.Count - 1))]
    [void]$batches.Add($batch)
}
Write-Host "Aantal batches: $($batches.Count) (grootte: $batchSize)" -ForegroundColor Yellow
Write-Host ""

# --- API CALLS ---
$results = @()
$errors = @()
$batchNum = 0

foreach ($batch in $batches) {
    $batchNum++
    Write-Host "Batch $batchNum/$($batches.Count) - mids $($batch[0])..$($batch[-1])..." -NoNewline

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")

    $body = @{
        time        = $timestamp
        version     = 2
        command     = "ElementPropertiesGetUI3"
        callingUrl  = $callingUrl
        constructor = @{
            auth         = $auth
            siteRightsID = $siteRightsID
        }
        parameters  = @{
            contextHandle = $contextHandle
            versionHash   = $versionHash
            renderColors  = @($batch)
        }
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $body -ContentType "application/json" -Headers @{
            "accept"          = "application/json, text/plain, */*"
            "accept-language" = "nl"
            "origin"          = "https://node2.build.dalux.com"
            "referer"         = "https://node2.build.dalux.com/"
        }

        if ($response.value) {
            foreach ($elem in $response.value) {
                # Native properties (ExternalID, Tag, Category, File Name)
                $nativeProps = @{}
                if ($elem.nativePropertyGroups) {
                    foreach ($group in $elem.nativePropertyGroups) {
                        foreach ($prop in $group.properties) {
                            $nativeProps[$prop.key] = $prop.value
                        }
                    }
                }

                # IfcGUID uit propertyGroups
                $ifcGuid = ""
                if ($elem.propertyGroups) {
                    foreach ($group in $elem.propertyGroups) {
                        foreach ($prop in $group.properties) {
                            if ($prop.key -eq "IfcGUID") {
                                $ifcGuid = $prop.value
                            }
                        }
                    }
                }

                # Dalux QR link
                $encodedUid = [uri]::EscapeDataString($elem.uniqueID)
                $encodedName = [uri]::EscapeDataString($elem.name)
                $qrString = "LandingPage%7C%3F$projectID%7C%3F3%7C%3F646911%7C%3F$encodedUid%7C%3F$encodedName"
                $daluxLink = "https://node2.field.dalux.com/service/qr/content?qrString=$qrString"

                $results += [PSCustomObject]@{
                    mid        = $elem.renderColor
                    name       = $elem.name
                    uniqueID   = $elem.uniqueID
                    externalID = if ($nativeProps['ExternalID']) { $nativeProps['ExternalID'] } else { "" }
                    ifcGUID    = $ifcGuid
                    tag        = if ($nativeProps['Tag']) { $nativeProps['Tag'] } else { "" }
                    category   = if ($nativeProps['Category']) { $nativeProps['Category'] } else { "" }
                    fileName   = if ($nativeProps['File Name']) { $nativeProps['File Name'] } else { "" }
                    daluxLink  = $daluxLink
                }
            }
            Write-Host " OK ($($response.value.Count) elementen)" -ForegroundColor Green
        }
        else {
            Write-Host " Leeg resultaat" -ForegroundColor Yellow
        }
    }
    catch {
        $errMsg = $_.Exception.Message
        Write-Host " FOUT: $errMsg" -ForegroundColor Red
        $errors += [PSCustomObject]@{
            batch   = "$($batch[0])..$($batch[-1])"
            error   = $errMsg
        }
    }

    Start-Sleep -Milliseconds 500
}

# --- EXPORT ---
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "RESULTATEN" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Elementen opgehaald: $($results.Count)" -ForegroundColor Green
Write-Host "Fouten:              $($errors.Count)" -ForegroundColor $(if ($errors.Count -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($results.Count -gt 0) {
    $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Host "CSV opgeslagen in: $outputFile" -ForegroundColor Green
    Write-Host ""
    Write-Host "Voorbeeld eerste 10 regels:" -ForegroundColor Cyan
    $results | Select-Object -First 10 | Format-Table mid, tag, uniqueID, externalID, ifcGUID, category -AutoSize
}

if ($errors.Count -gt 0) {
    Write-Host "Fouten:" -ForegroundColor Red
    $errors | Format-Table -AutoSize
}
