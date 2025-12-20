$ErrorActionPreference = "Stop"

# ===== KONFIGURACJA =====
$webhook = $env:DISCORD_WEBHOOK
if (-not $webhook) {
    Write-Error "Brak zmiennej DISCORD_WEBHOOK"
    exit 1
}

$stateFile = "state.json"
$knownIds = @()

if (Test-Path $stateFile) {
    $knownIds = Get-Content $stateFile | ConvertFrom-Json
    if ($null -eq $knownIds) { $knownIds = @() }
}

# ===== POBRANIE DANYCH Z EPIC =====
$url = "https://store-site-backend-static.ak.epicgames.com/freeGamesPromotions?locale=pl&country=PL&allowCountries=PL"
$data = Invoke-RestMethod -Uri $url -Method Get

$games = $data.data.Catalog.searchStore.elements
$now = Get-Date

$newFreeGames = @()

foreach ($game in $games) {
    Write-Output "Sprawdzam grę: $($game.title)"

    # Pomijamy DLC
    if ($game.offerType -eq "DLC") {
        Write-Output "  Pomijam – DLC"
        continue
    }

    $promotions = $game.promotions.promotionalOffers
    if (-not $promotions) {
        Write-Output "  Pomijam – brak promocji"
        continue
    }

    foreach ($promoBlock in $promotions) {
        foreach ($promo in $promoBlock.promotionalOffers) {

            $start = Get-Date $promo.startDate
            $end   = Get-Date $promo.endDate

            if ($now -lt $start -or $now -gt $end) {
                continue
            }

            $price = $game.price.totalPrice
            if (-not $price) {
                continue
            }

            if ($price.discountPrice -ne 0) {
                Write-Output "  Pomijam – cena końcowa ≠ 0"
                continue
            }

            if ($knownIds -contains $game.id) {
                Write-Output "  Pomijam – już wysłana"
                continue
            }

            Write-Output "  ✔ NOWA DARMOWA GRA"
            $newFreeGames += $game
        }
    }
}

# ===== WYSYŁKA NA DISCORD =====
foreach ($game in $newFreeGames) {

    $slug = $game.productSlug
    if (-not $slug) {
        $slug = $game.urlSlug
    }

    $link = "https://store.epicgames.com/pl/p/$slug"

    $image = $null
    foreach ($img in $game.keyImages) {
        if ($img.type -eq "OfferImageWide") {
            $image = $img.url
            break
        }
    }

    $payload = @{
        embeds = @(
            @{
                title = "Darmowa gra na Epic Games"
                description = "**$($game.title)** jest teraz dostępna **ZA DARMO**"
                url = $link
                color = 5763719
                image = @{ url = $image }
                footer = @{ text = "Epic Games Store" }
            }
        )
    } | ConvertTo-Json -Depth 10

    Invoke-RestMethod -Uri $webhook -Method Post -Body $payload -ContentType "application/json"

    $knownIds += $game.id
}

# ===== ZAPIS STATE =====
$knownIds | ConvertTo-Json | Set-Content $stateFile -Encoding UTF8

Write-Output "Zakończono. Nowe gry: $($newFreeGames.Count)"
