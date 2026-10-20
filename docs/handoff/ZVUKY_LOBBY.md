# Zvuky v lobby – co je kde slyšet (návod pro majitele)

Lobby má tiché zvuky prostředí. Slyšíš je jen zblízka a při čištění rudy se
ztiší. Všechny zvuky jsou od Robloxu, takže fungují hned a nic se nenahrává.

| Kde | Co uslyšíš |
|---|---|
| **Vodopády** (potok na jihu, vodopády v horách a u lomu) | šumění vody |
| **Potok u mostku** | tiché zurčení |
| **Rybníky** (koi, lekníny, rybníky na loukách, u potoka) | občas žbluňknutí a cvrčci |
| **Velká výheň** (průchod pod střechou) | praskání ohně ve dvou ohništích |
| **Vysoko v horách** | vítr, který sílí, čím výš jsi |
| **Náměstí** | zatím ticho (viz níže) |

## Dvě místa čekají na tebe (nepovinné)

Robloxí zvuky neumí lidi na náměstí ani žáby. Jestli je chceš:

1. V **Roblox Studiu** otevři **View → Toolbox → Marketplace → Audio**.
2. Najdi:
   - **náměstí:** „crowd murmur“ nebo „town ambience“ (tiché povídání lidí),
   - **žáby:** „frog“ (krátké kvákání).
3. Pusť si ukázku ▶. Když se ti líbí, klikni **pravým tlačítkem → Copy Asset ID**.
4. Pošli mi čísla do chatu:

```
Namesti = 1234567890
Zaby = ...
```

Já je vložím do hry. Hlasitost a vzdálenost už jsou nastavené.

## Pro vývojáře

Nastavení je v `src/shared/Config/AmbienceConfig.luau` (místa, vzdálenosti,
časovače, čísla pro majitele) a zvuky v `SoundConfig.luau` (klíče `Amb*`).
Místa značí server (`World/Lobby/Ambience.luau`), hraje je
`AmbienceController`. Hlasitost jde přes SoundGroup `TerraForgeAmbience`, až
bude menu s nastavením.
