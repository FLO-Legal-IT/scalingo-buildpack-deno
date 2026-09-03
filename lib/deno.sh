#!/usr/bin/env bash
# Download, verificatie en installatie van de Deno-runtime.
#
# Deno publiceert per platform twéé checksums: één voor het zip-archief en één
# voor de uitgepakte binary. We verifiëren beide: het archief vóór het
# uitpakken (dekt de download), de binary erna (dekt ook de uitpakstap zelf én
# de buildcache — een corrupte of vervuilde cache-binary komt er niet doorheen,
# want de verwachte binary-hash wordt elke build vers opgehaald).

# x86_64 hardcoded: de Scalingo-stacks zijn amd64. Komt daar ooit arm bij, dan
# hoort hier een uname -m-vertakking.
DENO_ARCHIVE="deno-x86_64-unknown-linux-gnu.zip"
DENO_BINARY_SUM="deno-x86_64-unknown-linux-gnu.sha256sum"

deno::release_url() {
  echo "https://github.com/denoland/deno/releases/download/${1}"
}

deno::fetch() {
  local url="${1}" dest="${2}"
  curl --fail --silent --show-error --location --retry 3 --output "${dest}" "${url}"
}

# Pakt het archief uit in de doelmap. unzip staat op de gewone stacks
# (gemeten, 2026-08-27); op de -minimal-varianten ontbreekt hij — dan falen we
# met een duidelijke melding in plaats van een cryptische.
deno::extract() {
  local archive="${1}" dest="${2}"
  if ! command -v unzip > /dev/null; then
    failure::no_unzip
  fi
  unzip -q -o "${archive}" -d "${dest}"
}

# Installeert de gevraagde versie in ${install_dir}/bin/deno, met de
# platform-buildcache als tussenstation zodat een herhaalde build niet opnieuw
# hoeft te downloaden.
deno::install() {
  local version="${1}" install_dir="${2}" cache_dir="${3}"
  local work cached expected
  work="$(mktemp -d)"
  cached="${cache_dir}/deno-${version}"

  # De verwachte binary-hash altijd vers ophalen (een bestand van één regel):
  # zo wordt óók een cache-treffer elke build opnieuw geverifieerd.
  deno::fetch "$(deno::release_url "${version}")/${DENO_BINARY_SUM}" \
    "${work}/${DENO_BINARY_SUM}" || failure::download "${version}"
  expected="$(cut -d' ' -f1 < "${work}/${DENO_BINARY_SUM}")"

  if [[ -x "${cached}" ]] \
    && echo "${expected}  ${cached}" | sha256sum --check --status -; then
    output::info "Deno ${version} uit de buildcache"
  else
    # Vóór de grote download: zonder unzip valt er straks toch niets uit te
    # pakken, dus dan is meteen falen 40 MB goedkoper.
    if ! command -v unzip > /dev/null; then
      failure::no_unzip
    fi
    output::info "Deno ${version} downloaden"
    deno::fetch "$(deno::release_url "${version}")/${DENO_ARCHIVE}" \
      "${work}/${DENO_ARCHIVE}" || failure::download "${version}"
    deno::fetch "$(deno::release_url "${version}")/${DENO_ARCHIVE}.sha256sum" \
      "${work}/${DENO_ARCHIVE}.sha256sum" || failure::download "${version}"
    (cd "${work}" && sha256sum --check --status "${DENO_ARCHIVE}.sha256sum") \
      || failure::checksum "${version}" "het archief"
    deno::extract "${work}/${DENO_ARCHIVE}" "${work}"
    echo "${expected}  ${work}/deno" | sha256sum --check --status - \
      || failure::checksum "${version}" "de uitgepakte binary"
    mkdir -p "${cache_dir}"
    mv "${work}/deno" "${cached}"
    chmod +x "${cached}"
  fi

  mkdir -p "${install_dir}/bin"
  cp "${cached}" "${install_dir}/bin/deno"
}
