$ErrorActionPreference = "Stop"

# ================== KONFIGURACJA ==================
$webhook = $env:DISCORD_WEBHOOK
if (-not $webhook) {
    Write-Error "Brak zmiennej DISCORD_WEBHOOK"
    exit 1
}

$stateFile = "state.json"

# ================== WCZYTANIE STANU (HASHTABLE) ==================
$knownGames = @{}

if (Test-Path $stateFile) {
    $json = Get-Content $stateFile | ConvertFrom-Json
    if ($json) {
        foreach ($prop in $json.PSObject.Properties) {
            $knownGames[$prop.Name] = $prop.Value
        }
    }
}

# ================== POBRANIE DANYCH Z EPIC ==================
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

            Write-Output "  ✔ NOWA DARMOWA GRA"
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

    $epicLink = "https://store.epicgames.com/pl/p/$slug"
    $endText = $end.ToString("dd.MM.yyyy HH:mm")

    $steamSearch = "https://store.steampowered.com/search/?term=" + `
        [System.Web.HttpUtility]::UrlEncode($game.title)

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
                title = "$($game.title)"
                url   = $epicLink
                color = 3447003
                description = @"
**Kliknij tytuł powyżej, aby przejść do strony gry**

**Darmowa do:** $endText  

*Kliknij tytuł gry powyżej, aby przejść do Epic Games Store*
"@
                image = @{ url = $image }
                fields = @(
                    @{
                        name  = "Linki"
                        value = "[Epic Games Store]($epicLink)`n[Steam – wyszukiwanie]($steamSearch)"
                        inline = $false
                    }
                )
                footer = @{
                    text = "Epic Games Store • Darmowe gry"
                }
                timestamp = (Get-Date).ToString("o")
            }
        )
    } | ConvertTo-Json -Depth 10

    Invoke-RestMethod -Uri $webhook -Method Post -Body $payload -ContentType "application/json"

    $knownGames[$game.id] = $game.title
}

# ================== ZAPIS STATE ==================
$knownGames | ConvertTo-Json -Depth 5 | Set-Content $stateFile -Encoding UTF8

Write-Output "Zakończono. Nowe gry: $($newFreeGames.Count)"
