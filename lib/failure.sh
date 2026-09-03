#!/usr/bin/env bash
# Eén functie per faalgeval. Elke melding benoemt het probleem én de oplossing.
# Patroon overgenomen uit lib/failure.sh van Scalingo/nodejs-buildpack.

failure::missing_procfile() {
  local build_dir="${1:-}"
  [[ -f "${build_dir}/Procfile" ]] && return 0

  output::header "Build mislukt"
  output::fail "Geen Procfile gevonden.

Deze buildpack raadt het startcommando niet. Maak een bestand Procfile in
de root van je project, bijvoorbeeld:

    web: deno run --allow-net --allow-env main.ts

Zorg dat je app luistert op \$PORT en op hostname 0.0.0.0."
}

failure::dot_scalingo_checked_in() {
  local build_dir="${1:-}"
  [[ -e "${build_dir}/.scalingo" && ! -d "${build_dir}/.scalingo" ]] || return 0

  output::header "Build mislukt"
  output::fail "Er staat een bestand .scalingo in je repository.

Deze buildpack gebruikt de map .scalingo om de Deno-runtime en de
dependencycache in te zetten. Verwijder het bestand uit versiebeheer, of
sluit het uit via .slugignore."
}

failure::invalid_version() {
  local version="${1:-}"

  output::header "Build mislukt"
  output::fail "Ongeldige Deno-versie: '${version}'

Geef een exacte versie op, geen range en geen 'latest'. Bijvoorbeeld:

    echo 'v2.5.0' > .deno-version

Een build die vandaag een andere runtime oplevert dan gisteren is geen
reproduceerbare build."
}

failure::download() {
  local version="${1:-}"

  output::header "Build mislukt"
  output::fail "Downloaden van Deno ${version} is mislukt.

Controleer of deze versie bestaat op:
https://github.com/denoland/deno/releases

Als de versie wel bestaat, was dit waarschijnlijk een tijdelijke
netwerkstoring. Push opnieuw om het nog eens te proberen."
}

failure::checksum() {
  local version="${1:-}" wat="${2:-de download}"

  output::header "Build mislukt"
  output::fail "Checksum van ${wat} klopt niet (Deno ${version}).

De inhoud komt niet overeen met de door Deno gepubliceerde sha256. De build
is afgebroken. Dit is geen fout die je moet negeren: onderzoek dit voordat
je opnieuw deployt."
}

failure::no_unzip() {
  output::header "Build mislukt"
  output::fail "unzip ontbreekt in deze buildomgeving.

Deno's Linux-release bestaat alleen als .zip, en deze omgeving heeft geen
unzip aan boord. Gemeten (2026-08-27): unzip staat op scalingo-22/-24/-26 en
ontbreekt op de -minimal-varianten. Zie je deze melding bij een echte deploy,
dan draait de build dus op een omgeving zonder unzip — dat is precies het
open punt uit de README; meld het."
}

failure::frozen_lockfile() {
  output::header "Build mislukt"
  output::fail "deno install --frozen is mislukt.

Je deno.lock komt niet overeen met de imports in je code. Draai lokaal:

    deno install

commit het bijgewerkte deno.lock, en push opnieuw."
}
