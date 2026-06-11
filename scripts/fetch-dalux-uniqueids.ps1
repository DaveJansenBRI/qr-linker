# ==============================================================
# Dalux UniqueID Fetcher v3 — via REST API
# Gebruikt de officiële Dalux API met API-sleutel
# ==============================================================

# --- CONFIGURATIE ---
$apiKey = "2124386:HWdB3Dh5LdbQFldz"
$baseUrl = "https://node2.field.dalux.com/service/api/4.0"
$headers = @{ "X-API-KEY" = $apiKey }

# --- BESTANDEN ---
$outputFile = "$PSScriptRoot\..\dalux_elements.csv"

# --- STAP 1: Projecten ophalen ---
Write-Host "=== STAP 1: Projecten ophalen ===" -ForegroundColor Cyan
try {
    $projects = Invoke-RestMethod -Uri "$baseUrl/projects" -Headers $headers -Method Get
    Write-Host "Projecten gevonden: $($projects.items.Count)" -ForegroundColor Green
    foreach ($p in $projects.items) {
        Write-Host "  [$($p.projectId)] $($p.projectName)" -ForegroundColor White
    }
} catch {
    Write-Host "FOUT bij projecten ophalen: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# --- Zoek het Vindingrijk project ---
$project = $projects.items | Where-Object { $_.projectName -like "*Vindingrijk*" -or $_.projectName -like "*3307*" -or $_.projectName -like "*Maassluis*" -or $_.projectName -like "*Nieuwbouw*" }
if (-not $project) {
    Write-Host "Vindingrijk project niet gevonden. Alle projecten:" -ForegroundColor Yellow
    $projects.items | ForEach-Object { Write-Host "  $($_.projectId) — $($_.projectName)" }
    $projectId = Read-Host "Voer het juiste projectId in"
} else {
    if ($project -is [array]) { $project = $project[0] }
    $projectId = $project.projectId
    Write-Host "Project gevonden: $($project.projectName) [$projectId]" -ForegroundColor Green
}

# --- STAP 2: Gebouwen ophalen ---
Write-Host ""
Write-Host "=== STAP 2: Gebouwen ophalen ===" -ForegroundColor Cyan
try {
    $buildings = Invoke-RestMethod -Uri "$baseUrl/projects/$projectId/buildings" -Headers $headers -Method Get
    Write-Host "Gebouwen gevonden: $($buildings.items.Count)" -ForegroundColor Green
    foreach ($b in $buildings.items) {
        Write-Host "  [$($b.buildingId)] $($b.buildingName)" -ForegroundColor White
    }
} catch {
    Write-Host "FOUT: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Probeer: /projects/$projectId" -ForegroundColor Yellow
    
    # Probeer project detail
    try {
        $detail = Invoke-RestMethod -Uri "$baseUrl/projects/$projectId" -Headers $headers -Method Get
        Write-Host "Project detail:" -ForegroundColor Cyan
        $detail | ConvertTo-Json -Depth 3 | Write-Host
    } catch {
        Write-Host "Kan project detail ook niet ophalen: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- STAP 3: BIM Models ophalen ---
Write-Host ""
Write-Host "=== STAP 3: BIM Models ophalen ===" -ForegroundColor Cyan

# Probeer verschillende API endpoints
$endpoints = @(
    "/projects/$projectId/bim/models",
    "/projects/$projectId/models",
    "/projects/$projectId/bim",
    "/projects/$projectId/files"
)

$modelsData = $null
foreach ($ep in $endpoints) {
    try {
        Write-Host "  Probeer: $ep ..." -NoNewline
        $modelsData = Invoke-RestMethod -Uri "$baseUrl$ep" -Headers $headers -Method Get
        Write-Host " OK!" -ForegroundColor Green
        $modelsData | ConvertTo-Json -Depth 3 | Write-Host
        break
    } catch {
        Write-Host " Nee ($($_.Exception.Response.StatusCode))" -ForegroundColor Yellow
    }
}

# --- STAP 4: Probeer elementen via building ---
if ($buildings -and $buildings.items) {
    Write-Host ""
    Write-Host "=== STAP 4: Elementen ophalen ===" -ForegroundColor Cyan
    
    foreach ($building in $buildings.items) {
        $bid = $building.buildingId
        Write-Host "Gebouw: $($building.buildingName) [$bid]" -ForegroundColor Cyan
        
        $elementEndpoints = @(
            "/projects/$projectId/buildings/$bid/elements",
            "/projects/$projectId/buildings/$bid/bim/elements",
            "/buildings/$bid/elements",
            "/projects/$projectId/buildings/$bid/objects"
        )
        
        foreach ($ep in $elementEndpoints) {
            try {
                Write-Host "  Probeer: $ep ..." -NoNewline
                $elemData = Invoke-RestMethod -Uri "$baseUrl$ep" -Headers $headers -Method Get
                Write-Host " OK!" -ForegroundColor Green
                
                # Toon eerste paar elementen
                if ($elemData.items) {
                    Write-Host "  Elementen: $($elemData.items.Count)" -ForegroundColor Green
                    $elemData.items | Select-Object -First 3 | ConvertTo-Json -Depth 3 | Write-Host
                } else {
                    $elemData | ConvertTo-Json -Depth 3 | Write-Host
                }
                break
            } catch {
                $code = $_.Exception.Response.StatusCode
                Write-Host " Nee ($code)" -ForegroundColor Yellow
            }
        }
    }
}

# --- STAP 5: Probeer ook de interne API met de API-key ---
Write-Host ""
Write-Host "=== STAP 5: Interne BimProxy API test ===" -ForegroundColor Cyan

$internalUrl = "https://node2.field.dalux.com/service-1-18/EntryPoints/Web/BimProxy.aspx/Web/ElementPropertiesGetUI3"
$testBody = @{
    time        = (Get-Date).ToUniversalTime().ToString("o")
    version     = 2
    command     = "ElementPropertiesGetUI3"
    callingUrl  = "https://node2.build.dalux.com/client/303048207527575552/location/default"
    constructor = @{
        auth         = $apiKey
        siteRightsID = 563307
    }
    parameters  = @{
        contextHandle = "b1646911tDEFAULT"
        versionHash   = 281617172
        renderColors  = @(55633)
    }
} | ConvertTo-Json -Depth 5

try {
    Write-Host "  Test met renderColor 55633..." -NoNewline
    $testResult = Invoke-RestMethod -Uri $internalUrl -Method Post -Body $testBody -ContentType "text/plain" -Headers @{
        "accept"  = "application/json, text/plain, */*"
        "origin"  = "https://node2.build.dalux.com"
        "referer" = "https://node2.build.dalux.com/"
    }
    
    if ($testResult.value -and $testResult.value.Count -gt 0) {
        Write-Host " OK!" -ForegroundColor Green
        Write-Host "  Element: $($testResult.value[0].name)" -ForegroundColor Cyan
        Write-Host "  UniqueID: $($testResult.value[0].uniqueID)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  ✅ Interne API werkt met API-key!" -ForegroundColor Green
        Write-Host "  Start bulk ophalen..." -ForegroundColor Cyan
        
        # --- BULK OPHALEN ---
        $inputFile = "$PSScriptRoot\..\img\mids_lijst.txt"
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
        
        # Gebruik mid kolom als renderColor
        $uniqueMids = $elements | Select-Object -ExpandProperty mid -Unique | Sort-Object
        Write-Host "  $($uniqueMids.Count) unieke mids" -ForegroundColor Green
        
        $batchSize = 50
        $batches = [System.Collections.ArrayList]@()
        for ($i = 0; $i -lt $uniqueMids.Count; $i += $batchSize) {
            $batch = $uniqueMids[$i..([Math]::Min($i + $batchSize - 1, $uniqueMids.Count - 1))]
            [void]$batches.Add($batch)
        }
        
        $results = @()
        $errors = @()
        $batchNum = 0
        
        foreach ($batch in $batches) {
            $batchNum++
            Write-Host "  Batch $batchNum/$($batches.Count)..." -NoNewline
            
            $body = @{
                time        = (Get-Date).ToUniversalTime().ToString("o")
                version     = 2
                command     = "ElementPropertiesGetUI3"
                callingUrl  = "https://node2.build.dalux.com/client/303048207527575552/location/default"
                constructor = @{ auth = $apiKey; siteRightsID = 563307 }
                parameters  = @{
                    contextHandle = "b1646911tDEFAULT"
                    versionHash   = 281617172
                    renderColors  = @($batch)
                }
            } | ConvertTo-Json -Depth 5
            
            try {
                $response = Invoke-RestMethod -Uri $internalUrl -Method Post -Body $body -ContentType "text/plain" -Headers @{
                    "accept"  = "application/json, text/plain, */*"
                    "origin"  = "https://node2.build.dalux.com"
                    "referer" = "https://node2.build.dalux.com/"
                }
                
                if ($response.value) {
                    foreach ($elem in $response.value) {
                        $nativeProps = @{}
                        if ($elem.nativePropertyGroups) {
                            foreach ($group in $elem.nativePropertyGroups) {
                                foreach ($prop in $group.properties) {
                                    $nativeProps[$prop.key] = $prop.value
                                }
                            }
                        }
                        $ifcGuid = ""
                        if ($elem.propertyGroups) {
                            foreach ($group in $elem.propertyGroups) {
                                foreach ($prop in $group.properties) {
                                    if ($prop.key -eq "IfcGUID") { $ifcGuid = $prop.value }
                                }
                            }
                        }
                        
                        $results += [PSCustomObject]@{
                            mid        = $elem.renderColor
                            name       = $elem.name
                            uniqueID   = $elem.uniqueID
                            externalID = if ($nativeProps['ExternalID']) { $nativeProps['ExternalID'] } else { "" }
                            ifcGUID    = $ifcGuid
                            tag        = if ($nativeProps['Tag']) { $nativeProps['Tag'] } else { "" }
                            category   = if ($nativeProps['Category']) { $nativeProps['Category'] } else { "" }
                            fileName   = if ($nativeProps['File Name']) { $nativeProps['File Name'] } else { "" }
                        }
                    }
                    Write-Host " OK ($($response.value.Count))" -ForegroundColor Green
                } else {
                    Write-Host " Leeg" -ForegroundColor Yellow
                }
            } catch {
                Write-Host " FOUT" -ForegroundColor Red
                $errors += $_.Exception.Message
            }
            
            Start-Sleep -Milliseconds 300
        }
        
        # Export
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "  Elementen opgehaald: $($results.Count)" -ForegroundColor Green
        Write-Host "  Fouten: $($errors.Count)" -ForegroundColor $(if ($errors.Count -gt 0) {"Red"} else {"Green"})
        Write-Host "========================================" -ForegroundColor Green
        
        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
            Write-Host "  CSV: $outputFile" -ForegroundColor Cyan
            $results | Select-Object -First 5 | Format-Table mid, tag, uniqueID, externalID, ifcGUID -AutoSize
        }
    } else {
        Write-Host " Leeg resultaat" -ForegroundColor Yellow
    }
} catch {
    Write-Host " Mislukt: $($_.Exception.Message)" -ForegroundColor Red
    
    # Laat error body zien
    try {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        Write-Host "  Response: $($reader.ReadToEnd())" -ForegroundColor Yellow
    } catch {}
}

Write-Host ""
Write-Host "Klaar!" -ForegroundColor Green
