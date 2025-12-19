$ErrorActionPreference = "Stop"

$webhook = $env:DISCORD_WEBHOOK
$api = "https://store-site-backend-static.ak.epicgames.com/freeGamesPromotions?locale=pl&country=PL"
$stateFile = "state.json"

# ===== Wczytaj poprzedni stan =====
if (Test-Path $stateFile) {
    $state = Get-Content $stateFile | ConvertFrom-Json
} else {
    $state = @{
        current = @()
        upcoming = @()
    }
}

# ===== Pobierz dane z Epic =====
$data = Invoke-RestMethod -Uri $api
$games = $data.data.Catalog.searchStore.elements
$now = Get-Date

$current = @()
$upcoming = @()

foreach ($game in $games) {

    # Akceptujemy BASE_GAME lub PACKAGE
    if ($game.offerType -notin @("BASE_GAME","PACKAGE")) { continue }
    if (-not $game.price) { continue }

    $price = $game.price.totalPrice
    # Uwzględniamy floaty w 100% zniżce
    if ([math]::Round($price.discountPercentage) -ne 100) { continue }
    if ($price.discountPrice -ne 0) { continue }

    # Jeśli brak promocji, pomiń
    if ($null -eq $game.promotions) { continue }

    # Pobierz wszystkie promocje (standard + upcoming + holiday)
    $allPromos = @()
    if ($game.promotions.promotionalOffers) { $allPromos += $game.promotions.promotionalOffers.promotionalOffers }
    if ($game.promotions.upcomingPromotionalOffers) { $allPromos += $game.promotions.upcomingPromotionalOffers.promotionalOffers }

    foreach ($offer in $allPromos) {
        $start = Get-Date $offer.startDate
        $end = Get-Date $offer.endDate

        # Sprawdzamy holiday sales (jeśli dostępne)
        $isHoliday = $false
        if ($offer.promotionType -eq "HOLIDAY_SALE") { $isHoliday = $true }

        # Dodajemy do current / upcoming
        if ($now -ge $start -and $now -le $end) {
            $current += $game
        } elseif ($now -lt $start) {
            $upcoming += $game
        }
    }
}

# ===== Filtruj tylko nowe gry względem state.json =====
$newCurrent = $current | Where-Object { $_.id -notin $state.current }
$newUpcoming = $upcoming | Where-Object { $_.id -notin $state.upcoming }

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
