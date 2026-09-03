#!/usr/bin/env bash
# Restore en save van DENO_DIR — de dependencycache van Deno — naar de
# buildcache van het platform.
#
# Waarom kopiëren en niet DENO_DIR meteen in CACHE_DIR leggen: de twee mappen
# hebben elk precies één eigenschap die we nodig hebben, en ze hebben ze niet
# allebei. Alleen wat onder BUILD_DIR staat reist mee de slug in (nodig: een
# app mag bij het booten niets meer hoeven downloaden), en alleen CACHE_DIR
# overleeft de build (nodig: anders begint de volgende build weer koud). Dus
# staat DENO_DIR onder BUILD_DIR en zetten we hem er hier omheen.
#
# De kopieerslag zelf is lokale I/O van een paar seconden; de downloads die ze
# bespaart duren een veelvoud daarvan.

# Ophogen zodra de indeling van de cachemap verandert: oude caches vervallen
# dan vanzelf bij de eerstvolgende build.
CACHE_FORMAT_VERSION="1"

# Vangnet tegen een cache die over honderden deploys blijft doorgroeien —
# DENO_DIR ruimt zichzelf niet op, en vanaf enige omvang kosten de twee
# kopieerslagen meer dan de downloads die ze besparen. Bij overschrijding
# vervalt de cache in zijn geheel: alles of niets, net als de cachesleutel.
CACHE_MAX_MB="${CACHE_MAX_MB:-512}"

# Vaste namen binnen CACHE_DIR. De runtime-binary staat daar als deno-vX.Y.Z,
# dus deze twee botsen er niet mee.
CACHE_STORE_NAME="deno-deps"
CACHE_STAMP_NAME="deno-deps.signature"

# De cachesleutel. Bewust grofmazig: de Deno-versie (DENO_DIR bevat door die
# versie gegenereerde artefacten) en de stack (gecompileerde npm-modules zijn
# aan de glibc van het image gebonden). De lockfile staat er bewust NIET in —
# juist bij een gewijzigde lock is de oude cache het meest waard, omdat verreweg
# de meeste packages hetzelfde blijven. Wat er niet meer bij hoort blijft dan
# als dood gewicht achter; daar is de limiet hierboven voor.
cache::signature() {
  local version="${1}" stack="${2:-onbekend}"
  echo "format=${CACHE_FORMAT_VERSION} deno=${version} stack=${stack}"
}

# Grootte in hele MB, of 0 als du er niet uitkomt: een mislukte meting mag de
# build niet breken, en 0 leidt overal tot het veilige gedrag.
cache::size_mb() {
  local size
  size="$({ du -sm "${1}" 2> /dev/null || true; } | cut -f1)"
  echo "${size:-0}"
}

# Verwijdert de bewaarde cache. Ook het pad waarlangs DENO_DEPS_CACHE=false een
# eerder bewaarde cache opruimt in plaats van hem alleen te negeren.
cache::clear() {
  local cache_dir="${1}"
  rm -rf "${cache_dir:?}/${CACHE_STORE_NAME}" "${cache_dir:?}/${CACHE_STAMP_NAME}"
}

# Zet een eerder bewaarde DENO_DIR terug in de buildmap.
cache::restore() {
  local cache_dir="${1}" target="${2}" signature="${3}"
  local store="${cache_dir}/${CACHE_STORE_NAME}"
  local stamp="${cache_dir}/${CACHE_STAMP_NAME}"
  local start end size

  if [[ ! -d "${store}" || ! -f "${stamp}" ]]; then
    output::info "dependency-cache: leeg, alles wordt opgehaald"
    cache::clear "${cache_dir}"
    return 0
  fi

  if [[ "$(cat "${stamp}")" != "${signature}" ]]; then
    output::info "dependency-cache: vervallen (andere versie of stack), wordt opnieuw opgebouwd"
    cache::clear "${cache_dir}"
    return 0
  fi

  start="$(date +%s)"
  mkdir -p "${target}"
  if ! cp -a "${store}/." "${target}/"; then
    # Een half teruggezette cache is gevaarlijker dan geen: een afgekapt
    # bestand komt er later uit als een onbegrijpelijke integriteitsfout in
    # deno zelf. Dus leeghalen en gewoon opnieuw ophalen.
    output::warn "Dependency-cache terugzetten is mislukt; de dependencies worden opnieuw opgehaald."
    rm -rf "${target:?}"
    mkdir -p "${target}"
    cache::clear "${cache_dir}"
    return 0
  fi
  end="$(date +%s)"

  size="$(cache::size_mb "${target}")"
  output::info "dependency-cache: ${size} MB teruggezet in $((end - start))s"
}

# Bewaart DENO_DIR voor de volgende build. Mag de build nooit laten falen: een
# mislukte save kost hooguit tijd bij de volgende deploy.
cache::save() {
  local cache_dir="${1}" source="${2}" signature="${3}"
  local store="${cache_dir}/${CACHE_STORE_NAME}"
  local stamp="${cache_dir}/${CACHE_STAMP_NAME}"
  local start end size

  [[ -d "${source}" ]] || return 0
  size="$(cache::size_mb "${source}")"

  # De stempel gaat er als eerste af. Een build die halverwege de kopieerslag
  # wordt afgebroken laat dan wel een halve map achter, maar geen stempel die
  # beweert dat hij klopt — de volgende build gooit hem weg.
  cache::clear "${cache_dir}"

  if ((size > CACHE_MAX_MB)); then
    output::info "dependency-cache: ${size} MB is meer dan de limiet van ${CACHE_MAX_MB} MB; niet bewaard"
    return 0
  fi

  start="$(date +%s)"
  mkdir -p "${store}"
  if ! cp -a "${source}/." "${store}/"; then
    output::warn "Dependency-cache bewaren is mislukt; de volgende build begint met een lege cache."
    cache::clear "${cache_dir}"
    return 0
  fi
  end="$(date +%s)"

  echo "${signature}" > "${stamp}"
  output::info "dependency-cache: ${size} MB bewaard in $((end - start))s"
}
