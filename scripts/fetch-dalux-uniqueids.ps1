# Dalux UniqueID Fetcher v3
# Gebruikt de Dalux REST API + BimProxy API

$apiKey = "2124386:HWdB3Dh5LdbQFldz"
$baseUrl = "https://node2.field.dalux.com/service/api/4.0"
$headers = @{ "X-API-KEY" = $apiKey }
$outputFile = "$PSScriptRoot\..\dalux_elements.csv"

# STAP 1: Projecten
Write-Host "STAP 1: Projecten ophalen" -ForegroundColor Cyan
try {
    $projects = Invoke-RestMethod -Uri "$baseUrl/projects" -Headers $headers -Method Get
    Write-Host "Projecten: $($projects.items.Count)" -ForegroundColor Green
    foreach ($p in $projects.items) {
        Write-Host "  [$($p.projectId)] $($p.projectName)"
    }
}
catch {
    Write-Host "FOUT: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# Zoek Vindingrijk
$project = $projects.items | Where-Object { $_.projectName -like "*Vindingrijk*" -or $_.projectName -like "*Maassluis*" }
if ($project -is [array]) { $project = $project[0] }
if ($project) {
    $projectId = $project.projectId
    Write-Host "Gevonden: $($project.projectName) [$projectId]" -ForegroundColor Green
}
else {
    Write-Host "Vindingrijk niet gevonden. Kies uit bovenstaande lijst." -ForegroundColor Yellow
    $projectId = Read-Host "Voer projectId in"
}

# STAP 2: Gebouwen
Write-Host ""
Write-Host "STAP 2: Gebouwen ophalen" -ForegroundColor Cyan
try {
    $buildings = Invoke-RestMethod -Uri "$baseUrl/projects/$projectId/buildings" -Headers $headers -Method Get
    Write-Host "Gebouwen: $($buildings.items.Count)" -ForegroundColor Green
    foreach ($b in $buildings.items) {
        Write-Host "  [$($b.buildingId)] $($b.buildingName)"
    }
}
catch {
    Write-Host "Gebouwen niet beschikbaar: $($_.Exception.Message)" -ForegroundColor Yellow
}

# STAP 3: Test interne BimProxy API
Write-Host ""
Write-Host "STAP 3: BimProxy API testen" -ForegroundColor Cyan
$internalUrl = "https://node2.field.dalux.com/service-1-18/EntryPoints/Web/BimProxy.aspx/Web/ElementPropertiesGetUI3"

$testBody = @{
    time = (Get-Date).ToUniversalTime().ToString("o")
    version = 2
    command = "ElementPropertiesGetUI3"
    callingUrl = "https://node2.build.dalux.com/client/303048207527575552/location/default"
    constructor = @{
        auth = $apiKey
        siteRightsID = 563307
    }
    parameters = @{
        contextHandle = "b1646911tDEFAULT"
        versionHash = 281617172
        renderColors = @(55633)
    }
} | ConvertTo-Json -Depth 5

$internalHeaders = @{
    "accept" = "application/json, text/plain, */*"
    "origin" = "https://node2.build.dalux.com"
    "referer" = "https://node2.build.dalux.com/"
}

$apiWorks = $false
try {
    $testResult = Invoke-RestMethod -Uri $internalUrl -Method Post -Body $testBody -ContentType "text/plain" -Headers $internalHeaders
    if ($testResult.value -and $testResult.value.Count -gt 0) {
        Write-Host "BimProxy werkt! Test element: $($testResult.value[0].name)" -ForegroundColor Green
        $apiWorks = $true
    }
    else {
        Write-Host "BimProxy: leeg resultaat" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "BimProxy mislukt: $($_.Exception.Message)" -ForegroundColor Red
    try {
        $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        Write-Host "Response: $($sr.ReadToEnd())" -ForegroundColor Yellow
    }
    catch {}
}

if (-not $apiWorks) {
    Write-Host ""
    Write-Host "BimProxy API werkt niet. Controleer de API key en probeer opnieuw." -ForegroundColor Red
    exit
}

# STAP 4: Mids inlezen en bulk ophalen
Write-Host ""
Write-Host "STAP 4: Bulk ophalen" -ForegroundColor Cyan
$inputFile = "$PSScriptRoot\..\img\mids_lijst.txt"
$lines = Get-Content $inputFile -Encoding UTF8 | Where-Object { $_ -match '^\d+\|' }
$mids = @()
foreach ($line in $lines) {
    $parts = $line.Split('|')
    if ($parts.Count -ge 3 -and $parts[0] -match '^\d+$') {
        $mid = [int]$parts[0]
        if ($mids -notcontains $mid) {
            $mids += $mid
        }
    }
}
$mids = $mids | Sort-Object
Write-Host "Unieke mids: $($mids.Count)" -ForegroundColor Green

$batchSize = 50
$results = @()
$errorCount = 0
$totalBatches = [Math]::Ceiling($mids.Count / $batchSize)

for ($i = 0; $i -lt $mids.Count; $i += $batchSize) {
    $end = [Math]::Min($i + $batchSize - 1, $mids.Count - 1)
    $batch = $mids[$i..$end]
    $batchNum = [Math]::Floor($i / $batchSize) + 1

    Write-Host "Batch $batchNum/$totalBatches ..." -NoNewline

    $body = @{
        time = (Get-Date).ToUniversalTime().ToString("o")
        version = 2
        command = "ElementPropertiesGetUI3"
        callingUrl = "https://node2.build.dalux.com/client/303048207527575552/location/default"
        constructor = @{
            auth = $apiKey
            siteRightsID = 563307
        }
        parameters = @{
            contextHandle = "b1646911tDEFAULT"
            versionHash = 281617172
            renderColors = @($batch)
        }
    } | ConvertTo-Json -Depth 5

    try {
        $resp = Invoke-RestMethod -Uri $internalUrl -Method Post -Body $body -ContentType "text/plain" -Headers $internalHeaders

        if ($resp.value) {
            foreach ($elem in $resp.value) {
                $np = @{}
                if ($elem.nativePropertyGroups) {
                    foreach ($g in $elem.nativePropertyGroups) {
                        foreach ($pr in $g.properties) {
                            $np[$pr.key] = $pr.value
                        }
                    }
                }
                $ifcGuid = ""
                if ($elem.propertyGroups) {
                    foreach ($g in $elem.propertyGroups) {
                        foreach ($pr in $g.properties) {
                            if ($pr.key -eq "IfcGUID") { $ifcGuid = $pr.value }
                        }
                    }
                }

                $obj = [PSCustomObject]@{
                    mid = $elem.renderColor
                    name = $elem.name
                    uniqueID = $elem.uniqueID
                    externalID = $(if ($np['ExternalID']) { $np['ExternalID'] } else { "" })
                    ifcGUID = $ifcGuid
                    tag = $(if ($np['Tag']) { $np['Tag'] } else { "" })
                    category = $(if ($np['Category']) { $np['Category'] } else { "" })
                    fileName = $(if ($np['File Name']) { $np['File Name'] } else { "" })
                }
                $results += $obj
            }
            Write-Host " OK ($($resp.value.Count) elementen)" -ForegroundColor Green
        }
        else {
            Write-Host " Leeg" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host " FOUT: $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }

    Start-Sleep -Milliseconds 300
}

# RESULTATEN
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Elementen opgehaald: $($results.Count)" -ForegroundColor Green
Write-Host "Fouten: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Green" })
Write-Host "========================================" -ForegroundColor Cyan

if ($results.Count -gt 0) {
    $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Host "CSV opgeslagen: $outputFile" -ForegroundColor Green
    Write-Host ""
    Write-Host "Eerste 10 elementen:" -ForegroundColor Cyan
    $results | Select-Object -First 10 | Format-Table mid, tag, uniqueID, externalID, ifcGUID -AutoSize
}

Write-Host "Klaar!" -ForegroundColor Green
