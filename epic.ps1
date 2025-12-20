$ErrorActionPreference = "Stop"

# ================== KONFIGURACJA ==================
$webhook = $env:DISCORD_WEBHOOK
if (-not $webhook) {
    Write-Error "Brak zmiennej DISCORD_WEBHOOK"
    exit 1
}

$stateFile = "state.json"

# ================== WCZYTANIE STANU ==================
$knownGames = @{}
if (Test-Path $stateFile) {
    $knownGames = Get-Content $stateFile | ConvertFrom-Json
    if ($null -eq $knownGames) { $knownGames = @{} }
}

# ================== POBRANIE DANYCH ==================
$url = "https://store-site-backend-static.ak.epicgames.com/freeGamesPromotions?locale=pl&country=PL&allowCountries=PL"
$data = Invoke-RestMethod -Uri $url -Method Get

$games = $data.data.Catalog.searchStore.elements
$now = Get-Date
$newFreeGames = @()

# ================== FILTROWANIE ==================
foreach ($game in $games) {
    Write-Output "Sprawdzam grę: $($game.title)"

    if ($game.offerType -eq "DLC") {
        Write-Output "  Pomijam – DLC"
        continue
    }

    $promoBlocks = $game.promotions.promotionalOffers
    if (-not $promoBlocks) {
        Write-Output "  Pomijam – brak promocji"
        continue
    }

    foreach ($block in $promoBlocks) {
        foreach ($promo in $block.promotionalOffers) {

            $start = Get-Date $promo.startDate
            $end   = Get-Date $promo.endDate

            if ($now -lt $start -or $now -gt $end) {
                continue
            }

            $price = $game.price.totalPrice
            if (-not $price -or $price.discountPrice -ne 0) {
                Write-Output "  Pomijam – cena ≠ 0"
                continue
            }

            if ($knownGames.ContainsKey($game.id)) {
                Write-Output "  Pomijam – już wysłana ($($knownGames[$game.id]))"
                continue
            }

            Write-Output "NOWA DARMOWA GRA"
            $newFreeGames += @{
                Game = $game
                End  = $end
            }
        }
    }
}

# ================== WYSYŁKA NA DISCORD ==================
foreach ($item in $newFreeGames) {

    $game = $item.Game
    $end  = $item.End

    $slug = $game.productSlug
    if (-not $slug) { $slug = $game.urlSlug }

    $link = "https://store.epicgames.com/pl/p/$slug"
    $endText = $end.ToString("dd.MM.yyyy HH:mm")

    $image = $null
    foreach ($img in $game.keyImages) {
        if ($img.type -eq "OfferImageWide") {
            $image = $img.url
            break
        }
    }

    # ===== ŁADNY EMBED =====
    $payload = @{
        embeds = @(
            @{
                title = "Darmowa gra na Epic Games Store"
                url = $link
                color = 3066993
                description = @"
**$($game.title)**

 **Cena:** Darmowa  
 **Dostępna do:** $endText  

 Kliknij tytuł lub grafikę, aby odebrać grę
"@
                image = @{ url = $image }
                footer = @{
                    text = "Epic Games Store • Darmowe gry"
                }
                timestamp = (Get-Date).ToString("o")
            }
        )
    } | ConvertTo-Json -Depth 10

    Invoke-RestMethod -Uri $webhook -Method Post -Body $payload -ContentType "application/json"

    # Zapis stanu
    $knownGames[$game.id] = $game.title
}

# ================== ZAPIS STATE.JSON ==================
$knownGames | ConvertTo-Json -Depth 5 | Set-Content $stateFile -Encoding UTF8

Write-Output "Zakończono. Nowe gry: $($newFreeGames.Count)"
