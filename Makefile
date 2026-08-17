# Docker Homelab – Independent Compose Projects
# Usage: make up | make down | make up-plex | make restart-caddy | make logs-caddy
# ──────────────────────────────────────────────────────────────────────────────

COMPOSE  = docker compose
ENVFILES = --env-file .env.common --env-file .env
DC       = $(COMPOSE) $(ENVFILES) -f

# Project paths (directory containing compose.yaml)
# NOTE: there is no TAILSCALE project. tailscaled runs on the host as a systemd
# unit since 2026-07-31 — Tailscale SSH serves the machine the daemon runs on, and
# in a container that was the container.
# See docs/setup.md.
CADDY        = caddy/compose.yaml
PLEX         = plex/compose.yaml
UNMANIC      = unmanic/compose.yaml
ADGUARD      = adguard/compose.yaml
KUMA         = kuma/compose.yaml
HOMEPAGE     = homepage/compose.yaml
CROWDSEC     = crowdsec/compose.yaml
DIUN         = diun/compose.yaml
SAMBA        = samba/compose.yaml
BORGMATIC    = borgmatic/compose.yaml
HOMEASSISTANT = homeassistant/compose.yaml
BITCOIN      = bitcoin-node/compose.yaml
SNOWFLAKE    = snowflake/compose.yaml
SCRUTINY     = scrutiny/compose.yaml
# Game servers (minecraft, vrising, …) run INSIDE pelican — wings creates one
# docker container per server; there are no per-game compose stacks anymore.
PELICAN      = pelican/compose.yaml

# All projects in startup order.
ALL_PROJECTS = CADDY ADGUARD PLEX UNMANIC KUMA HOMEPAGE \
               CROWDSEC DIUN SAMBA BORGMATIC HOMEASSISTANT BITCOIN SNOWFLAKE SCRUTINY \
               PELICAN

# Lowercase per-project target names (must match the PROJECT_TARGETS calls below).
# Order doesn't matter here — only used for order-independent fan-out (pull-parallel).
PROJECT_NAMES = caddy plex unmanic adguard kuma homepage \
                crowdsec diun samba borgmatic homeassistant bitcoin \
                snowflake scrutiny pelican

# Projects that use custom Dockerfiles and need `docker compose build`
BUILD_PROJECTS = CADDY

# ── Prune ────────────────────────────────────────────────────────
# Prune the system of all stopped containers, dangling images, and unused networks/volumes.

.PHONY: prune

prune:
	@echo "==> Image prune..."
	docker image prune -af
	@echo ""
	@echo "==> Builder prune..."
	docker builder prune -f
	@echo ""
	@echo "==> Volume prune..."
	docker volume prune -f
	@echo ""
# ── External networks ────────────────────────────────────────────────────────
# These must exist before any service that uses them. Idempotent (safe to re-run).

.PHONY: networks

networks:
	@docker network inspect proxy_network >/dev/null 2>&1 || \
		(echo "Creating proxy_network..." && \
		docker network create --driver bridge --subnet 172.20.0.0/16 proxy_network)
	@docker network inspect lan_macvlan >/dev/null 2>&1 || \
		(echo "Creating lan_macvlan..." && \
		docker network create -d macvlan \
			--subnet=192.168.0.0/24 \
			--gateway=192.168.0.1 \
			--ip-range=192.168.0.240/28 \
			-o parent=eno1 \
			lan_macvlan)

# ── Aggregate targets ────────────────────────────────────────────────────────

.PHONY: up down restart pull pull-parallel build status

up: networks
	@echo "==> Starting all projects..."
	@$(foreach p,$(ALL_PROJECTS),echo "  -> $(p)"; $(DC) $($(p)) up -d;)
	@echo "==> All projects started."

down:
	@echo "==> Stopping all projects..."
	@$(foreach p,$(ALL_PROJECTS),echo "  -> $(p)"; $(DC) $($(p)) down;)
	@echo "==> All projects stopped."

restart:
	@echo "==> Restarting all projects..."
	@$(foreach p,$(ALL_PROJECTS),echo "  -> $(p)"; $(DC) $($(p)) down; $(DC) $($(p)) up -d;)
	@echo "==> All projects restarted."

pull:
	@echo "==> Pulling images for all projects..."
	@$(foreach p,$(ALL_PROJECTS),echo "  -> $(p)"; $(DC) $($(p)) pull;)
	@echo "==> All images pulled."

# Parallel variant: fans out to the hidden _ppull-<name> targets (defined in
# PROJECT_TARGETS below), 6 projects at a time. Each prints a single ✓/✗ line;
# --output-sync=target keeps a failing project's error output grouped with its
# ✗ line, and -k lets the rest finish so one failure doesn't hide the others.
pull-parallel:
	@echo "==> Pulling images for all projects (6 in parallel)..."
	@if $(MAKE) -k -j6 --no-print-directory --output-sync=target \
			$(addprefix _ppull-,$(PROJECT_NAMES)); then \
		echo "==> All images pulled."; \
	else \
		echo "==> Pull FAILED for the project(s) marked ✗ above."; \
		exit 1; \
	fi

build:
	@echo "==> Building custom images..."
	@$(foreach p,$(BUILD_PROJECTS),echo "  -> $(p)"; $(DC) $($(p)) build;)
	@echo "==> All custom images built."

status:
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | sort

# ── Per-project targets ──────────────────────────────────────────────────────
# Usage: make up-<name>  |  make down-<name>  |  make restart-<name>
#        make logs-<name> |  make pull-<name>

define PROJECT_TARGETS
.PHONY: up-$(1) down-$(1) restart-$(1) logs-$(1) pull-$(1) build-$(1) _ppull-$(1)
up-$(1):
	$(DC) $($(2)) up -d
down-$(1):
	$(DC) $($(2)) down
restart-$(1):
	$(DC) $($(2)) down
	$(DC) $($(2)) up -d
logs-$(1):
	$(DC) $($(2)) logs -f --tail=100
pull-$(1):
	$(DC) $($(2)) pull
build-$(1):
	$(DC) $($(2)) build
# Quiet worker for `make pull-parallel`: one ✓/✗ line per project instead of
# 6 interleaved progress bars.
_ppull-$(1):
	@$(DC) $($(2)) pull --quiet \
		&& echo "  ✓ $(1)" \
		|| { echo "  ✗ $(1) FAILED"; exit 1; }
endef

$(eval $(call PROJECT_TARGETS,caddy,CADDY))
$(eval $(call PROJECT_TARGETS,plex,PLEX))
$(eval $(call PROJECT_TARGETS,unmanic,UNMANIC))
$(eval $(call PROJECT_TARGETS,adguard,ADGUARD))
$(eval $(call PROJECT_TARGETS,kuma,KUMA))
$(eval $(call PROJECT_TARGETS,homepage,HOMEPAGE))
$(eval $(call PROJECT_TARGETS,crowdsec,CROWDSEC))
$(eval $(call PROJECT_TARGETS,diun,DIUN))
$(eval $(call PROJECT_TARGETS,samba,SAMBA))
$(eval $(call PROJECT_TARGETS,borgmatic,BORGMATIC))
$(eval $(call PROJECT_TARGETS,homeassistant,HOMEASSISTANT))
$(eval $(call PROJECT_TARGETS,bitcoin,BITCOIN))
$(eval $(call PROJECT_TARGETS,snowflake,SNOWFLAKE))
$(eval $(call PROJECT_TARGETS,scrutiny,SCRUTINY))
$(eval $(call PROJECT_TARGETS,pelican,PELICAN))


# ── Help ─────────────────────────────────────────────────────────────────────

.PHONY: help
help:
	@echo "Docker Homelab Management"
	@echo ""
	@echo "Aggregate commands:"
	@echo "  make networks  Create external networks (proxy_network, lan_macvlan)"
	@echo "  make up        Create networks + start all projects"
	@echo "  make down      Stop all projects"
	@echo "  make restart   Restart all projects"
	@echo "  make pull      Pull all images (serial, full progress output)"
	@echo "  make pull-parallel  Pull all images, 6 projects at a time (quiet, ✓/✗ per project)"
	@echo "  make build     Build custom images (e.g. Caddy)"
	@echo "  make status    Show running containers"
	@echo "  make prune     Remove unused resources"
	@echo ""
	@echo "Per-project commands (replace <name>):"
	@echo "  make up-<name>       Start a project"
	@echo "  make down-<name>     Stop a project"
	@echo "  make restart-<name>  Restart a project"
	@echo "  make logs-<name>     Tail logs"
	@echo "  make pull-<name>     Pull images"
	@echo "  make build-<name>    Build custom image"
