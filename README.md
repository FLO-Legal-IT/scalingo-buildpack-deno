# Deno-buildpack voor Scalingo

Draait Deno-applicaties op Scalingo. Installeert een gepinde Deno-runtime met
checksumverificatie, draait `deno install` en een optionele buildtask.

## Gebruik

    scalingo -a app-naam env-set BUILDPACK_URL="https://github.com/FLO-Legal-IT/scalingo-buildpack-deno#v1"

Pin altijd op een release-branch of tag. Wijs nooit naar de default branch: een
commit op vrijdagmiddag mag de deploy van een collega op maandag niet breken.

Wil je de buildpack niet publiek hosten, laat `BUILDPACK_URL` dan eindigen op
`.tar.gz` of `.tgz` — Scalingo downloadt en pakt dat archief uit, dus een
release-tarball op eigen hosting kan ook.

## Wat je project nodig heeft

| Bestand | Verplicht | Betekenis |
|---|---|---|
| `deno.json` of `deno.jsonc` | ja | Detectie-trigger |
| `Procfile` | ja | Startcommando |
| `deno.lock` | aanbevolen | `deno install --frozen` |
| `.deno-version` | nee | Pint de runtime; zonder geldt de default van de buildpack |

Vier env-vars sturen de build:

| Variabele | Betekenis |
|---|---|
| `DENO_VERSION` | Runtime-versie, alléén gelezen als `.deno-version` ontbreekt; zelfde `vX.Y.Z`-eis |
| `DENO_BUILD_TASK` | Naam van de buildtask (default `build`); draait alleen als hij in `deno.json` bestaat |
| `DENO_DEPS_CACHE` | Op `false` zet de dependencycache uit én ruimt de bewaarde cache op |
| `DENO_DEPS_CACHE_MAX_MB` | Verhoogt de grens waarboven de cache vervalt (default 512) |

`Procfile`:

    web: deno run --allow-net --allow-env main.ts

Je app moet luisteren op `$PORT` en op `0.0.0.0`:

```ts
Deno.serve({
  port: Number(Deno.env.get("PORT") ?? 8000),
  hostname: "0.0.0.0",
}, handler);
```

## Caching

Twee dingen overleven een build: de Deno-runtime en de dependencies. Allebei
staan ze in de buildcache van het platform, en allebei komen ze bij de volgende
deploy terug zonder download. `DENO_DIR` staat tijdens de build onder
`BUILD_DIR`, want alleen wat daar staat reist mee de slug in — je app hoeft bij
het booten dus nooit iets op te halen — en de buildpack kopieert die map heen en
weer naar de buildcache, want alleen díé overleeft de build.

De cachesleutel is de Deno-versie plus de stack. Verandert er één van, dan
vervalt de hele cache. De lockfile zit er bewust **niet** in: juist bij een
gewijzigde lock is de oude cache het meest waard, omdat verreweg de meeste
packages hetzelfde blijven. Wat er niet meer bij hoort blijft dan als dood
gewicht achter; boven de 512 MB wordt de cache in zijn geheel weggegooid, want
vanaf enige omvang kosten de twee kopieerslagen meer dan de downloads die ze
besparen. Is jouw `DENO_DIR` legitiem groter, verhoog dan
`DENO_DEPS_CACHE_MAX_MB`.

Loopt er iets mis met de cache, of wil je één keer schoon bouwen:

    scalingo -a app-naam env-set DENO_DEPS_CACHE=false

Die deploy ruimt de bewaarde cache op. Zet de variabele daarna weer terug
(`env-unset`), anders bouw je voortaan elke keer koud.

## App-specifieke initialisatie

De buildpack schrijft `.profile.d/deno.sh` om `PATH` en `DENO_DIR` te zetten.
Die map is van de buildpack; zet daar niets van je applicatie in. Heb je een
eigen opstartstap nodig, gebruik dan een `.profile`-script in de root van je
project. Dat draait gegarandeerd ná alles in `.profile.d/`, dus `deno` staat er
al in je `PATH`.

## Combineren met andere buildpacks

Werkt in een multi-buildpackketen: `bin/compile` schrijft een `export`-bestand
met `PATH` en `DENO_DIR`, zodat een volgende buildpack (nginx, APT) `deno` al in
zijn `PATH` heeft staan.

## Ontwerpkeuzes

**Geen default startcommando.** De Node-buildpack raadt het startcommando als de
`Procfile` ontbreekt. Dat levert deploys op die draaien maar iets anders doen dan
je denkt. Deze buildpack faalt met een melding die laat zien wat er in de
`Procfile` moet.

**Exacte versies, in een eigen bestand.** `.deno-version` accepteert alleen
`vX.Y.Z`. Een build die vandaag een andere runtime oplevert dan gisteren is geen
reproduceerbare build. Het is een apart bestand omdat `deno.json` geen veld voor
de runtimeversie kent dat we mogen kapen — en het maakt de cachesleutel triviaal.

**Checksumverificatie is verplicht, niet optioneel.** Er wordt een binary van een
externe host gehaald en gedraaid in een omgeving waar de env-vars van je app
beschikbaar zijn. Deno publiceert twee hashes — voor het zip-archief en voor de
uitgepakte binary — en allebei worden ze gecontroleerd.

**Eén alles-of-niets cachesleutel**, geen gedeeltelijke invalidatie. De vier
buildpaden in de Node-buildpack komen voort uit pogingen de cache slim te
repareren. Die complexiteit erven we niet: een cache klopt of hij vervalt.

## Tests

    make test-all

De suite draait ook zonder Docker (`BP_DIR=$PWD TEST_DIR=$PWD/test bash
test/run.sh`), maar dat is geen vervanging: juist de verschillen tussen de stacks
zijn wat we willen afvangen. Tests die in `/app` schrijven worden buiten de
container overgeslagen.

## Licentie

MIT, met uitzondering van `test/shunit2`: dat is Apache License 2.0 (Copyright
Kate Ward), volledige tekst in `test/LICENSE-shunit2`. Bevat verder patronen
afgeleid van `Scalingo/nodejs-buildpack` (MIT) en `chibat/heroku-buildpack-deno`
(MIT); zie `LICENSE` voor de attributie.

---

*Deze buildpack is geschreven met hulp van [Claude Code](https://claude.com/claude-code).*
