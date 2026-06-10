# ==============================================================
# Dalux UniqueID Fetcher
# Haalt uniqueIDs op via de Dalux BIM API voor alle elementen
# ==============================================================

# --- CONFIGURATIE ---
$auth = "422080:QBzhlg34RRJhhmvI"
$siteRightsID = 563307
$contextHandle = "b1646911tDEFAULT"
$versionHash = 281617172
$projectID = "303048207527575552"
$callingUrl = "https://node2.build.dalux.com/client/$projectID/location/default"
$apiUrl = "https://node2.field.dalux.com/service-1-18/EntryPoints/Web/BimProxy.aspx/Web/ElementPropertiesGet2"

# --- BESTANDEN ---
$inputFile = "$PSScriptRoot\..\img\mids_lijst.txt"
$outputFile = "$PSScriptRoot\..\dalux_elements.csv"

# --- LEES MIDS ---
Write-Host "Mids inlezen..." -ForegroundColor Cyan
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

# --- BATCH GROOTTE ---
$batchSize = 50  # Aantal mids per API-call (pas aan als nodig)
$batches = [System.Collections.ArrayList]@()
for ($i = 0; $i -lt $uniqueMids.Count; $i += $batchSize) {
    $batch = $uniqueMids[$i..([Math]::Min($i + $batchSize - 1, $uniqueMids.Count - 1))]
    [void]$batches.Add($batch)
}
Write-Host "Aantal batches: $($batches.Count) (grootte: $batchSize)" -ForegroundColor Yellow

# --- API CALLS ---
$results = @()
$batchNum = 0

foreach ($batch in $batches) {
    $batchNum++
    Write-Host "Batch $batchNum/$($batches.Count) - mids $($batch[0])..$($batch[-1])..." -NoNewline

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")
    $renderColors = $batch -join ","

    $body = @{
        time        = $timestamp
        version     = 2
        command     = "ElementPropertiesGet2"
        callingUrl  = $callingUrl
        constructor = @{
            auth         = $auth
            siteRightsID = $siteRightsID
        }
        parameters  = @{
            contextHandle     = $contextHandle
            versionHash       = $versionHash
            renderColors      = $batch
            includeProperties = $true
        }
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $body -ContentType "text/plain" -Headers @{
            "accept"          = "application/json, text/plain, */*"
            "accept-language" = "nl"
            "origin"          = "https://node2.build.dalux.com"
            "referer"         = "https://node2.build.dalux.com/"
        }

        if ($response.value) {
            foreach ($elem in $response.value) {
                $code = ""
                if ($elem.elementProperties) {
                    $codeProp = $elem.elementProperties | Where-Object { $_.name -eq "Code" }
                    if ($codeProp) { $code = $codeProp.value }
                }

                $results += [PSCustomObject]@{
                    mid       = $elem.renderColor
                    eid       = $elem.elementID
                    name      = $elem.name
                    uniqueID  = $elem.uniqueID
                    code      = $code
                    daluxLink = "https://node2.field.dalux.com/service/qr/content?qrString=LandingPage%7C%3F$projectID%7C%3F3%7C%3F646911%7C%3F$([uri]::EscapeDataString($elem.uniqueID))%7C%3F$([uri]::EscapeDataString($elem.name))"
                }
            }
            Write-Host " OK ($($response.value.Count) elementen)" -ForegroundColor Green
        }
        else {
            Write-Host " Leeg resultaat" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host " FOUT: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Wacht even om rate limiting te voorkomen
    Start-Sleep -Milliseconds 500
}

# --- EXPORT ---
Write-Host ""
Write-Host "Resultaten opslaan..." -ForegroundColor Cyan
$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Host "Klaar! $($results.Count) elementen opgeslagen in:" -ForegroundColor Green
Write-Host $outputFile -ForegroundColor White
Write-Host ""
Write-Host "Voorbeeld eerste 5 regels:" -ForegroundColor Cyan
$results | Select-Object -First 5 | Format-Table mid, eid, code, uniqueID -AutoSize
