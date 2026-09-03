# Alle drie publiek pullbaar van Docker Hub — bevestigd 2026-08-26 met een
# echte pull tijdens `make test` (een eerdere aanname dat scalingo-26 er niet
# stond bleek onjuist).
STACKS := scalingo-22 scalingo-24 scalingo-26

# De minimal-varianten missen tooling die de gewone stacks wel hebben.
# Daar valt een ontbrekende unzip als eerste door de mand.
MINIMAL_STACKS := scalingo-22-minimal scalingo-24-minimal

BUILD_TARGETS := $(addsuffix -build,$(STACKS) $(MINIMAL_STACKS))

.PHONY: test test-minimal test-all lint shell $(BUILD_TARGETS)

test: $(addsuffix -build,$(STACKS))

test-minimal: $(addsuffix -build,$(MINIMAL_STACKS))

test-all: test test-minimal

# Een STATISCHE patroonregel, bewust geen kale `%-build:`. De build-targets
# staan in .PHONY, en GNU make slaat voor phony targets de zoektocht langs
# impliciete regels over ("make skips the implicit rule search for phony
# targets") — patroonregels zijn impliciete regels, dus een gewone `%-build:`
# wordt voor deze targets nooit gevonden en `make test` strandt op
# "No rule to make target". Een statische patroonregel is een expliciete
# regel en heeft daar geen last van.
#
# --pull always staat er bewust in: een verouderde lokale image zou precies
# de stack-wijzigingen maskeren die we hier willen opvangen.
$(BUILD_TARGETS): %-build:
	@echo "==> $*"
	docker run --pull always --rm \
	  --env STACK=$* \
	  --volume $(PWD):/buildpack:ro \
	  --volume $(PWD)/test:/test:ro \
	  scalingo/$*:latest \
	  bash /test/run.sh

# Interactieve shell in dezelfde omgeving als een echte build, met de mounts
# en de STACK-variabele zoals de Scalingo-documentatie ze voorschrijft.
# Binnen de container:
#   mkdir /tmp/{cache,env}
#   /buildpack/bin/compile /build /tmp/cache /tmp/env
shell: STACK ?= scalingo-24
shell:
	docker run --pull always --rm --interactive --tty \
	  --env STACK=$(STACK) \
	  --volume $(PWD):/buildpack:ro \
	  --volume $(PWD)/test/fixtures/minimal:/build \
	  scalingo/$(STACK):latest bash

lint:
	shellcheck bin/detect bin/compile bin/release lib/*.sh
