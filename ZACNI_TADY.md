# Terra Forge – začni tady (česky)

## Jak hru spustit v Roblox Studiu (nejjednodušší cesta)
1. Na GitHubu otevři složku `build` → soubor `TerraForge.rbxl` → **Download raw file**.
2. Dvakrát na něj klikni – otevře se v Roblox Studiu.
3. Zmáčkni **Play** (F5). Mapa, světla i všechny skripty už jsou uvnitř.
4. Zveřejnění hry: **File → Publish to Roblox** a pak postupuj podle `PUBLISHING.md`.

## Když chceš měnit kód a vidět změny hned (Rojo)
Návod krok za krokem je v `docs/ROJO_SETUP.md` (VS Code + rozšíření „Rojo“,
pak v Studiu **Plugins → Rojo → Connect**).

## Co musíš udělat ručně
Krátký seznam je v `docs/STUDIO_CHECKLIST.md` (hlavně zapnout
**Game Settings → Security → Enable Studio Access to API Services**, aby fungovalo ukládání).

## Kde co je
- **Balanc hry** (rudy, ceny, stroje): `src/shared/Config/`
- **Příběh, rudy, stroje, ekonomika:** `docs/GAME_DESIGN.md`
- **Co otestovat po každém kroku:** `docs/QA_REPORTS.md`
- **Zveřejnění hry krok za krokem:** `PUBLISHING.md`
