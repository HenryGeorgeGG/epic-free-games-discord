$ErrorActionPreference = "Stop"

$webhook = $env:DISCORD_WEBHOOK
$api = "https://store-site-backend-static.ak.epicgames.com/freeGamesPromotions?locale=pl&country=PL"
$stateFile = "state.json"

# ===== Stan =====
if (Test-Path $stateFile) {
    $state = Get-Content $stateFile | ConvertFrom-Json
} else {
    $state = @{
        current = @()
        upcoming = @()
    }
}

# ===== Dane =====
$data = Invoke-RestMethod -Uri $api
$games = $data.data.Catalog.searchStore.elements
$now = Get-Date

$current = @()
$upcoming = @()

foreach ($game in $games) {

    # ❌ pomijamy DLC, dodatki, bundle
    if ($game.offerType -ne "BASE_GAME") { continue }
    if (-not $game.price) { continue }

    $price = $game.price.totalPrice

    # MUSI BYĆ 100% OFF
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

# ===== Nowe =====
$newCurrent = $current | Where-Object { $_.id -notin $state.current }
$newUpcoming = $upcoming | Where-Object { $_.id -notin $state.upcoming }

if ($newCurrent.Count -eq 0 -and $newUpcoming.Count -eq 0) {
    Write-Output "Brak nowych darmowych gier"
    exit 0
}

# ===== Wiadomość =====
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

# ===== Wyślij =====
Invoke-RestMethod -Uri $webhook -Method Post -ContentType "application/json" -Body (@{
    content = $msg
} | ConvertTo-Json)

# ===== Zapis =====
$state.current = $current.id
$state.upcoming = $upcoming.id
$state | ConvertTo-Json | Set-Content $stateFile

