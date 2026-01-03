.PHONY: help build up down logs clean restart status shell info

# Color output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

# All runners
ALL_RUNNERS := tenfive-runner tensix-runner tenseven-runner teneight-runner tennine-runner tenten-runner

help:
	@echo "$(BLUE)BlakePorts Docker Runners - Makefile$(NC)"
	@echo ""
	@echo "$(YELLOW)NOTE: Use 'ghrunner' script for runner management$(NC)"
	@echo "      ghrunner handles VM startup, token generation, and config"
	@echo ""
	@echo "$(GREEN)Quick Start (via ghrunner):$(NC)"
	@echo "  ../scripts/ghrunner -vmware tenfive     - Start tenfive runner"
	@echo "  ../scripts/ghrunner -start-group legacy - Start all legacy runners"
	@echo ""
	@echo "$(GREEN)Container Management:$(NC)"
	@echo "  make build         - Build runner images"
	@echo "  make up            - Start all containers (requires config)"
	@echo "  make down          - Stop all containers"
	@echo "  make restart       - Restart all containers"
	@echo "  make status        - Check container status"
	@echo "  make logs          - View container logs"
	@echo ""
	@echo "$(GREEN)Cleanup:$(NC)"
	@echo "  make clean         - Stop containers and remove volumes"
	@echo ""
	@echo "$(GREEN)Debugging:$(NC)"
	@echo "  make shell RUNNER=<name>   - Shell into a container"
	@echo "  make config                - View current config"
	@echo ""
	@echo "$(GREEN)Files:$(NC)"
	@echo "  config/runners.json    - Runner config (tokens, IPs) - gitignored"
	@echo "  config.example.json    - Config template"
	@echo "  docker-compose.yml     - Service definitions"

# ============================================================================
# BUILD
# ============================================================================

build:
	@echo "$(BLUE)Building runner images...$(NC)"
	docker compose build
	@echo "$(GREEN)✓ Build complete$(NC)"

# ============================================================================
# CONTAINER MANAGEMENT
# ============================================================================

up:
	@if [ ! -f config/runners.json ]; then \
		echo "$(RED)Error: config/runners.json not found$(NC)"; \
		echo "Run: $(GREEN)../scripts/ghrunner -vmware <runner>$(NC) to generate config"; \
		exit 1; \
	fi
	@echo "$(BLUE)Starting containers...$(NC)"
	docker compose up -d
	@echo "$(GREEN)✓ Containers started$(NC)"
	@sleep 2
	@docker compose ps

up-single:
	@if [ -z "$(RUNNER)" ]; then \
		echo "$(RED)Error: RUNNER variable required$(NC)"; \
		echo "Usage: make up-single RUNNER=tenfive-runner"; \
		exit 1; \
	fi
	@echo "$(BLUE)Starting runner: $(RUNNER)$(NC)"
	docker compose up -d $(RUNNER)
	@echo "$(GREEN)✓ $(RUNNER) started$(NC)"

down:
	@echo "$(BLUE)Stopping containers...$(NC)"
	docker compose down
	@echo "$(GREEN)✓ Containers stopped$(NC)"

down-single:
	@if [ -z "$(RUNNER)" ]; then \
		echo "$(RED)Error: RUNNER variable required$(NC)"; \
		echo "Usage: make down-single RUNNER=tenfive-runner"; \
		exit 1; \
	fi
	@echo "$(BLUE)Stopping runner: $(RUNNER)$(NC)"
	docker compose stop $(RUNNER)
	@echo "$(GREEN)✓ $(RUNNER) stopped$(NC)"

restart:
	@echo "$(BLUE)Restarting containers...$(NC)"
	docker compose restart
	@echo "$(GREEN)✓ Containers restarted$(NC)"

logs:
	@docker compose logs -f

status:
	@echo "$(BLUE)Container Status:$(NC)"
	@echo ""
	@docker compose ps
	@echo ""
	@echo "$(BLUE)Config Status:$(NC)"
	@if [ -f config/runners.json ]; then \
		echo "$(GREEN)✓ config/runners.json exists$(NC)"; \
		jq -r '.runners | to_entries[] | "  \(.key): token=\(if .value.token != "" then "set" else "missing" end) ip=\(.value.vm_ip // "missing")"' config/runners.json 2>/dev/null || echo "  $(RED)Invalid JSON$(NC)"; \
	else \
		echo "$(YELLOW)⚠ config/runners.json not found$(NC)"; \
	fi

# ============================================================================
# CLEANUP
# ============================================================================

clean:
	@echo "$(BLUE)Stopping containers and removing volumes...$(NC)"
	docker compose down -v
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

clean-images:
	@echo "$(RED)Removing built images...$(NC)"
	docker compose down -v
	docker images --filter "reference=docker-*-runner" -q | xargs -r docker rmi
	@echo "$(GREEN)✓ Images removed$(NC)"

# ============================================================================
# DEBUGGING
# ============================================================================

shell:
	@if [ -z "$(RUNNER)" ]; then \
		echo "$(RED)Error: RUNNER variable required$(NC)"; \
		echo "Usage: make shell RUNNER=tenfive-runner"; \
		exit 1; \
	fi
	@echo "$(BLUE)Connecting to $(RUNNER)...$(NC)"
	docker compose exec $(RUNNER) bash

config:
	@echo "$(BLUE)Current Configuration:$(NC)"
	@echo ""
	@if [ -f config/runners.json ]; then \
		jq '.' config/runners.json; \
	else \
		echo "$(YELLOW)No config file found. Run ghrunner to generate.$(NC)"; \
	fi

# ============================================================================
# INFO
# ============================================================================

info:
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)     BlakePorts Docker Runners$(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(GREEN)Available Runners:$(NC)"
	@for runner in $(ALL_RUNNERS); do \
		echo "  • $$runner"; \
	done
	@echo ""
	@echo "$(GREEN)Configuration:$(NC)"
	@echo "  • Config stored in: config/runners.json"
	@echo "  • Managed by: ghrunner script"
	@echo "  • Tokens are regenerated on each runner start"
	@echo ""
	@echo "$(GREEN)Workflow:$(NC)"
	@echo "  1. ghrunner starts VMware VM on darkstar"
	@echo "  2. ghrunner resolves Bonjour hostname to IP"
	@echo "  3. ghrunner generates token and updates config"
	@echo "  4. ghrunner starts/restarts Docker container"
	@echo "  5. Container reads config and connects to VM via SSH"
	@echo ""
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
