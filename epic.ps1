$ErrorActionPreference = "Stop"

$webhook = $env:DISCORD_WEBHOOK
$api = "https://store-site-backend-static.ak.epicgames.com/freeGamesPromotions?locale=pl&country=PL"
$stateFile = "state.json"

# ===== Wczytaj poprzedni stan =====
if (Test-Path $stateFile) {
    $state = Get-Content $stateFile | ConvertFrom-Json
    Write-Output "Wczytano state.json z $($state.current.Count) current i $($state.upcoming.Count) upcoming"
} else {
    $state = @{
        current = @()
        upcoming = @()
    }
    Write-Output "Nie znaleziono state.json, utworzono nowy stan"
}

# ===== Pobierz dane z Epic =====
$data = Invoke-RestMethod -Uri $api
$games = $data.data.Catalog.searchStore.elements
$now = Get-Date

Write-Output ("Znaleziono {0} gier w API" -f $games.Count)

$current = @()
$upcoming = @()

foreach ($game in $games) {
    Write-Output ("Sprawdzam grę: {0}" -f $game.title)

    if ($game.offerType -notin @("BASE_GAME","PACKAGE")) { 
        Write-Output "  Pomijam – nie BASE_GAME ani PACKAGE"
        continue
    }
    if (-not $game.price) { 
        Write-Output "  Pomijam – brak ceny"
        continue
    }

    $price = $game.price.totalPrice
    if ([math]::Round($price.discountPercentage) -ne 100 -or $price.discountPrice -ne 0) {
        Write-Output "  Pomijam – nie 100% OFF"
        continue
    }

    if ($null -eq $game.promotions) { 
        Write-Output "  Pomijam – brak promocji"
        continue
    }

    $allPromos = @()
    if ($game.promotions.promotionalOffers) { $allPromos += $game.promotions.promotionalOffers.promotionalOffers }
    if ($game.promotions.upcomingPromotionalOffers) { $allPromos += $game.promotions.upcomingPromotionalOffers.promotionalOffers }

    if ($allPromos.Count -eq 0) { 
        Write-Output "  Pomijam – brak aktywnych promocji w polach promotionalOffers"
        continue
    }

    foreach ($offer in $allPromos) {
        $start = Get-Date $offer.startDate
        $end = Get-Date $offer.endDate
        if ($now -ge $start -and $now -le $end) {
            Write-Output "  Dodano do current"
            $current += $game
        } elseif ($now -lt $start) {
            Write-Output "  Dodano do upcoming"
            $upcoming += $game
        }
    }
}

# ===== Filtruj tylko nowe gry względem state.json =====
$newCurrent = $current | Where-Object { $_.id -notin $state.current }
$newUpcoming = $upcoming | Where-Object { $_.id -notin $state.upcoming }

Write-Output ("Nowe current: {0}, nowe upcoming: {1}" -f $newCurrent.Count, $newUpcoming.Count)

if ($newCurrent.Count -eq 0 -and $newUpcoming.Count -eq 0) {
    Write-Output "Brak nowych gier do wysłania"
    exit 0
}

# ===== Tworzenie wiadomości =====
$msg = ""

if ($newCurrent.Count -gt 0) {
    $msg += "**🎮 Darmowe gry do odebrania (0 zł):**`n`n"
    foreach ($g in $newCurrent) {
        $url = "https://store.epicgames.com/pl/p/$($g.productSlug)"
        $msg += "• **$($g.title)**`n$url`n`n"
    }
}

if ($newUpcoming.Count -gt 0) {
    $msg += "**⏳ Nadchodzące darmowe gry:**`n`n"
    foreach ($g in $newUpcoming) {
        $url = "https://store.epicgames.com/pl/p/$($g.productSlug)"
        $msg += "• **$($g.title)**`n$url`n`n"
    }
}

# ===== Wyślij wiadomość na Discord =====
Invoke-RestMethod -Uri $webhook -Method Post -ContentType "application/json" -Body (@{
    content = $msg
} | ConvertTo-Json)

# ===== Zapisz stan =====
$state.current = $current.id
$state.upcoming = $upcoming.id
$state | ConvertTo-Json | Set-Content $stateFile
Write-Output "Zaktualizowano state.json z {0} current i {1} upcoming" -f $current.Count, $upcoming.Count
