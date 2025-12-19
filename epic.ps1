$ErrorActionPreference = "Stop"

$webhook = $env:DISCORD_WEBHOOK
$api = "https://store-site-backend-static.ak.epicgames.com/freeGamesPromotions?locale=pl&country=PL"

# Pobierz dane z Epic
$data = Invoke-RestMethod -Uri $api
$games = $data.data.Catalog.searchStore.elements
$now = Get-Date

$current = @()
$upcoming = @()

foreach ($game in $games) {
    # Tylko pełne gry, pomijamy DLC i bundle
    if ($game.offerType -ne "BASE_GAME") { continue }
    if (-not $game.price) { continue }

    $price = $game.price.totalPrice

    # Tylko 100% OFF
    if ($price.discountPercentage -ne 100) { continue }
    if ($price.discountPrice -ne 0) { continue }

    if ($null -eq $game.promotions) { continue }

    foreach ($promo in $game.promotions.promotionalOffers) {
        foreach ($offer in $promo.promotionalOffers) {
            $start = Get-Date $offer.startDate
            $end = Get-Date $offer.endDate

            if ($now -ge $start -and $now -le $end) {
                $current += $game
            }
            elseif ($now -lt $start) {
                $upcoming += $game
            }
        }
    }
}

if ($current.Count -eq 0 -and $upcoming.Count -eq 0) {
    Write-Output "Brak darmowych gier"
    exit 0
}

# Tworzenie wiadomości
$msg = ""

if ($current.Count -gt 0) {
    $msg += "**🎮 Darmowe gry do odebrania (0 zł):**`n`n"
    foreach ($g in $current) {
        $url = "https://store.epicgames.com/pl/p/$($g.productSlug)"
        $msg += "• **$($g.title)**`n$url`n`n"
    }
}

if ($upcoming.Count -gt 0) {
    $msg += "**⏳ Nadchodzące darmowe gry:**`n`n"
    foreach ($g in $upcoming) {
        $url = "https://store.epicgames.com/pl/p/$($g.productSlug)"
        $msg += "• **$($g.title)**`n$url`n`n"
    }
}

# Wyślij wiadomość na Discord
Invoke-RestMethod -Uri $webhook -Method Post -ContentType "application/json" -Body (@{
    content = $msg
} | ConvertTo-Json)
