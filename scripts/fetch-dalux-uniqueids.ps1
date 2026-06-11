# Dalux UniqueID Fetcher - Simpel
# Leest renderColors uit mids_lijst.txt, haalt uniqueIDs op

$auth = "2124438:7IkAdI5ga8YxsfbY"
$apiUrl = "https://node2.field.dalux.com/service-1-18/EntryPoints/Web/BimProxy.aspx/Web/ElementPropertiesGetUI3"
$inputFile = "$PSScriptRoot\..\img\mids_lijst.txt"
$outputFile = "$PSScriptRoot\..\dalux_elements.csv"

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

# Batches maken
$batchSize = 50
$results = @()
$fouten = 0
$totaal = [Math]::Ceiling($mids.Count / $batchSize)

for ($i = 0; $i -lt $mids.Count; $i += $batchSize) {
    $batch = $mids[$i..([Math]::Min($i + $batchSize - 1, $mids.Count - 1))]
    $nr = [Math]::Floor($i / $batchSize) + 1
    Write-Host "Batch $nr/$totaal ..." -NoNewline

    $body = '{"time":"' + (Get-Date).ToUniversalTime().ToString("o") + '","version":2,"command":"ElementPropertiesGetUI3","callingUrl":"https://node2.build.dalux.com/client/303048207527575552/location/default","constructor":{"auth":"' + $auth + '","siteRightsID":563307},"parameters":{"contextHandle":"b1646911tDEFAULT","versionHash":281617172,"renderColors":[' + ($batch -join ',') + ']}}'

    try {
        $r = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $body -ContentType "text/plain"
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
