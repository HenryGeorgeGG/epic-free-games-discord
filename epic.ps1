$webhook = $env:DISCORD_WEBHOOK
$api = "https://store-site-backend-static.ak.epicgames.com/freeGamesPromotions?locale=pl&country=PL"

$data = Invoke-RestMethod -Uri $api -Method Get
$games = $data.data.Catalog.searchStore.elements

$now = Get-Date
$freeGames = @()

foreach ($game in $games) {
    if ($null -eq $game.promotions) { continue }

    foreach ($promo in $game.promotions.promotionalOffers) {
        foreach ($offer in $promo.promotionalOffers) {
            $start = Get-Date $offer.startDate
            $end = Get-Date $offer.endDate

            if ($now -ge $start -and $now -le $end) {
                $freeGames += $game
            }
        }
    }
}

if ($freeGames.Count -eq 0) {
    Write-Output "Brak darmowych gier"
    exit 0
}

$message = "**🎮 Darmowe gry na Epic Games Store:**`n`n"

foreach ($g in $freeGames) {
    $url = "https://store.epicgames.com/pl/p/$($g.productSlug)"
    $message += "• **$($g.title)**`n$url`n`n"
}

Invoke-RestMethod -Uri $webhook -Method Post -ContentType "application/json" -Body (@{
    content = $message
} | ConvertTo-Json)
