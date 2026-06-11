# Dalux UniqueID Fetcher
# Haalt uniqueIDs op via BimProxy met sessie-token

$auth = "422080:XjSBnew27FiCj6bd"
$apiUrl = "https://node2.field.dalux.com/service-1-18/EntryPoints/Web/BimProxy.aspx/Web/ElementPropertiesGet2"
$inputFile = "$PSScriptRoot\..\img\mids_lijst.txt"
$outputFile = "$PSScriptRoot\..\dalux_elements.csv"

$reqHeaders = @{
    "accept"          = "application/json, text/plain, */*"
    "accept-language" = "nl"
    "origin"          = "https://node2.build.dalux.com"
    "referer"         = "https://node2.build.dalux.com/"
    "sec-fetch-dest"  = "empty"
    "sec-fetch-mode"  = "cors"
    "sec-fetch-site"  = "same-site"
    "user-agent"      = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"
}

# Test eerst
Write-Host "Test met renderColor 55524..." -NoNewline
$testBody = '{"time":"' + (Get-Date).ToUniversalTime().ToString("o") + '","version":2,"command":"ElementPropertiesGet2","callingUrl":"https://node2.build.dalux.com/client/303048207527575552/location/default","constructor":{"auth":"' + $auth + '","siteRightsID":563307},"parameters":{"contextHandle":"b1646911tDEFAULT","versionHash":281617172,"renderColors":[55524],"includeProperties":true}}'
try {
    $test = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $testBody -ContentType "text/plain" -Headers $reqHeaders
    if ($test.result -and $test.result -eq 8) {
        Write-Host " FOUT: $($test.message)" -ForegroundColor Red
        Write-Host "Token is verlopen. Haal een nieuwe uit Chrome (F12 > Network > klik element > Payload > auth)" -ForegroundColor Yellow
        exit
    }
    Write-Host " OK!" -ForegroundColor Green
    $test | ConvertTo-Json -Depth 3 | Write-Host
} catch {
    Write-Host " FOUT: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# Mids inlezen
Write-Host "Mids inlezen..." -ForegroundColor Cyan
$mids = @()
Get-Content $inputFile -Encoding UTF8 | ForEach-Object {
    if ($_ -match '^(\d+)\|(\d+)\|(.+)$') {
        $mid = [int]$Matches[1]
        if ($mids -notcontains $mid) { $mids += $mid }
    }
}
$mids = $mids | Sort-Object
Write-Host "Unieke renderColors: $($mids.Count)"

# Bulk ophalen
$batchSize = 50
$results = @()
$fouten = 0
$totaal = [Math]::Ceiling($mids.Count / $batchSize)

for ($i = 0; $i -lt $mids.Count; $i += $batchSize) {
    $batch = $mids[$i..([Math]::Min($i + $batchSize - 1, $mids.Count - 1))]
    $nr = [Math]::Floor($i / $batchSize) + 1
    Write-Host "Batch $nr/$totaal ..." -NoNewline

    $body = '{"time":"' + (Get-Date).ToUniversalTime().ToString("o") + '","version":2,"command":"ElementPropertiesGet2","callingUrl":"https://node2.build.dalux.com/client/303048207527575552/location/default","constructor":{"auth":"' + $auth + '","siteRightsID":563307},"parameters":{"contextHandle":"b1646911tDEFAULT","versionHash":281617172,"renderColors":[' + ($batch -join ',') + '],"includeProperties":true}}'

    try {
        $r = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $body -ContentType "text/plain" -Headers $reqHeaders
        if ($r.value) {
            foreach ($el in $r.value) {
                $results += [PSCustomObject]@{
                    renderColor = $el.renderColor
                    elementID   = $el.elementID
                    name        = $el.name
                    uniqueID    = $el.uniqueID
                }
            }
            Write-Host " OK ($($r.value.Count))" -ForegroundColor Green
        } elseif ($r.result -eq 8) {
            Write-Host " Server error" -ForegroundColor Red
            $fouten++
        } else {
            Write-Host " Leeg" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host " FOUT: $($_.Exception.Message)" -ForegroundColor Red
        $fouten++
    }
    Start-Sleep -Milliseconds 300
}

Write-Host ""
Write-Host "Elementen: $($results.Count)" -ForegroundColor Green
Write-Host "Fouten: $fouten" -ForegroundColor $(if ($fouten -gt 0) {"Red"} else {"Green"})

if ($results.Count -gt 0) {
    $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Host "CSV: $outputFile" -ForegroundColor Green
    $results | Select-Object -First 10 | Format-Table -AutoSize
}
