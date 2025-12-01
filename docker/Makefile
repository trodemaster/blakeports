.PHONY: help tokens setup build up down logs clean restart status shell-tenfive shell-tenseven verify-hostnames check-env check-dependencies create-env-if-needed generate-tokens build-images unregister-runners stop-containers clean-images info

# Color output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

# GitHub configuration
GITHUB_OWNER := trodemaster
GITHUB_REPO := blakeports

# Active runners
ACTIVE_RUNNERS := tenfive-runner tenseven-runner

# All runners (for reference)
ALL_RUNNERS := tenfive-runner tenseven-runner tensix-runner teneight-runner tennine-runner tenten-runner

help:
	@echo "$(BLUE)BlakePorts Docker Runners - Makefile$(NC)"
	@echo ""
	@echo "$(GREEN)Quick Start:$(NC)"
	@echo "  make build         - Fully automated: generates tokens, builds images, ready for deployment"
	@echo "  make up            - Start containers"
	@echo "  make logs          - View container logs"
	@echo ""
	@echo "$(GREEN)Advanced Setup:$(NC)"
	@echo "  make tokens        - Generate fresh GitHub runner registration tokens"
	@echo "  make setup         - Setup .env and generate tokens (interactive)"
	@echo ""
	@echo "$(GREEN)Container Management:$(NC)"
	@echo "  make down          - Stop containers"
	@echo "  make restart       - Restart containers"
	@echo "  make status        - Check container status"
	@echo ""
	@echo "$(GREEN)Cleanup:$(NC)"
	@echo "  make clean         - Stop containers and unregister runners from GitHub"
	@echo "  make clean-images  - Remove built images"
	@echo ""
	@echo "$(GREEN)Debugging:$(NC)"
	@echo "  make shell-tenfive    - SSH into tenfive-runner container"
	@echo "  make shell-tenseven   - SSH into tenseven-runner container"
	@echo "  make verify-hostnames - Test SSH hostname resolution"
	@echo ""
	@echo "$(YELLOW)Important Notes:$(NC)"
	@echo "  • $(BLUE)make build$(NC) handles everything: tokens, .env, images, ready to deploy"
	@echo "  • Each runner needs its OWN registration token (single-use per runner)"
	@echo "  • Tokens expire after 1 hour if unused"
	@echo "  • .env file is gitignored and contains secrets - never commit it"

# ============================================================================
# SETUP AND CONFIGURATION
# ============================================================================

tokens:
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)     GitHub Runner Token Generation$(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(YELLOW)⚠️  IMPORTANT: Each runner needs its OWN token (single-use)$(NC)"
	@echo ""
	@echo "Generating tokens for:"
	@for runner in $(ACTIVE_RUNNERS); do \
		echo "  • $$runner"; \
	done
	@echo ""
	@echo "Proceeding to generate tokens..."
	@echo ""
	@echo "$(GREEN)Step 1: Generating RUNNER_TOKEN_TENFIVE...$(NC)"
	@echo "Press Enter when ready..."
	@read -p "Press Enter to continue" dummy
	@TENFIVE_TOKEN=$$(gh api repos/$(GITHUB_OWNER)/$(GITHUB_REPO)/actions/runners/registration-token --method POST --jq '.token'); \
	echo "$(GREEN)✓ RUNNER_TOKEN_TENFIVE=$(NC)$$TENFIVE_TOKEN"; \
	echo "$(YELLOW)Copy this token and save it$(NC)"; \
	echo ""
	@echo "$(GREEN)Step 2: Generating RUNNER_TOKEN_TENSEVEN...$(NC)"
	@echo "Press Enter when ready..."
	@read -p "Press Enter to continue" dummy
	@TENSEVEN_TOKEN=$$(gh api repos/$(GITHUB_OWNER)/$(GITHUB_REPO)/actions/runners/registration-token --method POST --jq '.token'); \
	echo "$(GREEN)✓ RUNNER_TOKEN_TENSEVEN=$(NC)$$TENSEVEN_TOKEN"; \
	echo "$(YELLOW)Copy this token and save it$(NC)"; \
	echo ""
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "Next: Edit .env and paste the tokens into:"
	@echo "  RUNNER_TOKEN_TENFIVE=<paste-token-here>"
	@echo "  RUNNER_TOKEN_TENSEVEN=<paste-token-here>"
	@echo ""
	@echo "Then run: $(GREEN)make up$(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"

setup:
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)     BlakePorts Docker Runners - Setup$(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@if [ ! -f .env ]; then \
		echo "$(YELLOW)Creating .env from example.env...$(NC)"; \
		cp example.env .env; \
		echo "$(GREEN)✓ .env created$(NC)"; \
	else \
		echo "$(GREEN)✓ .env already exists$(NC)"; \
	fi
	@echo ""
	@echo "$(YELLOW)Checking prerequisites...$(NC)"
	@command -v gh >/dev/null 2>&1 || { echo "$(RED)✗ gh CLI not found$(NC)"; exit 1; }; \
	echo "$(GREEN)✓ gh CLI available$(NC)"
	@command -v docker-compose >/dev/null 2>&1 || { echo "$(RED)✗ docker-compose not found$(NC)"; exit 1; }; \
	echo "$(GREEN)✓ docker-compose available$(NC)"
	@echo ""
	@echo "$(BLUE)Verifying GitHub access...$(NC)"
	@gh auth status 2>/dev/null | grep "Logged in to" > /dev/null || { echo "$(RED)✗ Not authenticated to GitHub$(NC)"; exit 1; }; \
	echo "$(GREEN)✓ GitHub authentication OK$(NC)"
	@echo ""
	@$(MAKE) tokens
	@echo ""
	@echo "$(BLUE)Setup complete! Next steps:$(NC)"
	@echo "  1. Edit .env and fill in the RUNNER_TOKEN_* values"
	@echo "  2. Run: $(GREEN)make build$(NC)"
	@echo "  3. Run: $(GREEN)make up$(NC)"

# ============================================================================
# CONTAINER MANAGEMENT
# ============================================================================

build: check-dependencies create-env-if-needed generate-tokens build-images up
	@echo ""
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)     Build and Deployment Complete!$(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(GREEN)Containers are running and registered!$(NC)"
	@echo ""
	@echo "Monitor with:$(NC)"
	@echo "  make logs        - Follow container logs"
	@echo "  make status      - Check container status"
	@echo ""

check-dependencies:
	@echo "$(BLUE)Checking prerequisites...$(NC)"
	@command -v gh >/dev/null 2>&1 || { echo "$(RED)✗ gh CLI not found$(NC)"; exit 1; }; \
	echo "$(GREEN)✓ gh CLI available$(NC)"
	@command -v docker >/dev/null 2>&1 || { echo "$(RED)✗ docker not found$(NC)"; exit 1; }; \
	echo "$(GREEN)✓ docker available$(NC)"
	@gh auth status 2>/dev/null | grep "Logged in to" > /dev/null || { echo "$(RED)✗ Not authenticated to GitHub$(NC)"; exit 1; }; \
	echo "$(GREEN)✓ GitHub authentication OK$(NC)"

create-env-if-needed:
	@if [ ! -f .env ]; then \
		echo "$(BLUE)Creating .env from example.env...$(NC)"; \
		cp example.env .env; \
		echo "$(GREEN)✓ .env created$(NC)"; \
	else \
		echo "$(GREEN)✓ .env already exists$(NC)"; \
	fi

generate-tokens:
	@echo ""
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)     Generating Registration Tokens$(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(YELLOW)⚠️  IMPORTANT: Each runner needs its OWN token (single-use)$(NC)"
	@echo ""
	@TENFIVE=$$(grep "^RUNNER_TOKEN_TENFIVE=" .env | cut -d= -f2); \
	if [ -n "$$TENFIVE" ] && [ "$$TENFIVE" != "" ]; then \
		echo "$(GREEN)✓ RUNNER_TOKEN_TENFIVE already set, skipping generation$(NC)"; \
	else \
		echo "$(BLUE)Generating RUNNER_TOKEN_TENFIVE...$(NC)"; \
		TENFIVE_TOKEN=$$(gh api repos/$(GITHUB_OWNER)/$(GITHUB_REPO)/actions/runners/registration-token --method POST --jq '.token' 2>/dev/null); \
		if [ -z "$$TENFIVE_TOKEN" ]; then \
			echo "$(RED)✗ Failed to generate RUNNER_TOKEN_TENFIVE$(NC)"; \
			exit 1; \
		fi; \
		sed -i '' "s/^RUNNER_TOKEN_TENFIVE=.*/RUNNER_TOKEN_TENFIVE=$$TENFIVE_TOKEN/" .env; \
		echo "$(GREEN)✓ RUNNER_TOKEN_TENFIVE generated and written to .env$(NC)"; \
	fi
	@echo ""
	@TENSEVEN=$$(grep "^RUNNER_TOKEN_TENSEVEN=" .env | cut -d= -f2); \
	if [ -n "$$TENSEVEN" ] && [ "$$TENSEVEN" != "" ]; then \
		echo "$(GREEN)✓ RUNNER_TOKEN_TENSEVEN already set, skipping generation$(NC)"; \
	else \
		echo "$(BLUE)Generating RUNNER_TOKEN_TENSEVEN...$(NC)"; \
		TENSEVEN_TOKEN=$$(gh api repos/$(GITHUB_OWNER)/$(GITHUB_REPO)/actions/runners/registration-token --method POST --jq '.token' 2>/dev/null); \
		if [ -z "$$TENSEVEN_TOKEN" ]; then \
			echo "$(RED)✗ Failed to generate RUNNER_TOKEN_TENSEVEN$(NC)"; \
			exit 1; \
		fi; \
		sed -i '' "s/^RUNNER_TOKEN_TENSEVEN=.*/RUNNER_TOKEN_TENSEVEN=$$TENSEVEN_TOKEN/" .env; \
		echo "$(GREEN)✓ RUNNER_TOKEN_TENSEVEN generated and written to .env$(NC)"; \
	fi
	@echo ""

build-images:
	@echo "$(BLUE)Building runner images...$(NC)"
	docker compose build
	@echo "$(GREEN)✓ Build complete$(NC)"

up: check-env
	@echo "$(BLUE)Starting containers...$(NC)"
	@echo ""
	@echo "$(YELLOW)Active runners:$(NC)"
	@for runner in $(ACTIVE_RUNNERS); do \
		echo "  • $$runner"; \
	done
	@echo ""
	docker compose up -d
	@echo ""
	@echo "$(GREEN)✓ Containers started$(NC)"
	@echo ""
	@echo "Checking container status (wait 5 seconds)..."
	@sleep 5
	@docker compose ps
	@echo ""
	@echo "$(BLUE)View logs with: $(GREEN)make logs$(NC)"

down:
	@echo "$(BLUE)Stopping containers...$(NC)"
	docker compose down
	@echo "$(GREEN)✓ Containers stopped$(NC)"

restart:
	@echo "$(BLUE)Restarting containers...$(NC)"
	@$(MAKE) down
	@sleep 2
	@$(MAKE) up

logs:
	@docker compose logs -f

status:
	@echo "$(BLUE)Container Status:$(NC)"
	@echo ""
	@docker compose ps
	@echo ""
	@echo "$(BLUE)Recent Logs (last 20 lines per container):$(NC)"
	@echo ""
	@for runner in $(ACTIVE_RUNNERS); do \
		echo "$(YELLOW)--- $$runner ---$(NC)"; \
		docker compose logs --tail=20 $$runner; \
		echo ""; \
	done

# ============================================================================
# CLEANUP
# ============================================================================

clean: unregister-runners stop-containers
	@echo ""
	@echo "$(BLUE)Removing container volumes and networks...$(NC)"
	docker compose down -v
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

unregister-runners:
	@echo "$(RED)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(RED)     Unregistering Runners from GitHub$(NC)"
	@echo "$(RED)═══════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(YELLOW)Fetching registered runners from GitHub...$(NC)"
	@RUNNERS_JSON=$$(gh api repos/$(GITHUB_OWNER)/$(GITHUB_REPO)/actions/runners --jq '.runners' 2>/dev/null); \
	if [ $$? -ne 0 ]; then \
		echo "$(RED)✗ Failed to fetch runners from GitHub API$(NC)"; \
		exit 1; \
	fi; \
	RUNNER_COUNT=$$(echo "$$RUNNERS_JSON" | jq 'length' 2>/dev/null); \
	if [ "$$RUNNER_COUNT" = "0" ] || [ -z "$$RUNNER_COUNT" ]; then \
		echo "$(BLUE)No runners found in GitHub API$(NC)"; \
	else \
		echo "$(YELLOW)Found $$RUNNER_COUNT runner(s) to remove$(NC)"; \
		echo "$$RUNNERS_JSON" | jq -r '.[] | "\(.id)|\(.name)"' | while IFS='|' read -r runner_id runner_name; do \
			if [ -n "$$runner_id" ] && [ -n "$$runner_name" ]; then \
				echo "$(YELLOW)  Removing '$$runner_name' (ID: $$runner_id)...$(NC)"; \
				if gh api repos/$(GITHUB_OWNER)/$(GITHUB_REPO)/actions/runners/$$runner_id --method DELETE 2>/dev/null; then \
					echo "$(GREEN)  ✓ Successfully removed '$$runner_name'$(NC)"; \
				else \
					echo "$(RED)  ✗ Failed to remove '$$runner_name'$(NC)"; \
				fi; \
			fi; \
		done; \
		echo ""; \
		echo "$(BLUE)Waiting for GitHub to process unregistration...$(NC)"; \
		sleep 3; \
	fi
	@echo ""

stop-containers:
	@echo "$(BLUE)Stopping containers...$(NC)"
	docker compose down 2>/dev/null || true
	@echo "$(GREEN)✓ Containers stopped$(NC)"

clean-images:
	@echo "$(RED)Removing built images...$(NC)"
	docker compose down -v
	docker rmi $$(docker images -q 'docker-tenfive-runner' 'docker-tenseven-runner' 2>/dev/null) 2>/dev/null || true
	@echo "$(GREEN)✓ Images removed$(NC)"

# ============================================================================
# DEBUGGING
# ============================================================================

shell-tenfive:
	@echo "$(BLUE)Connecting to tenfive-runner...$(NC)"
	docker compose exec tenfive-runner bash

shell-tenseven:
	@echo "$(BLUE)Connecting to tenseven-runner...$(NC)"
	docker compose exec tenseven-runner bash

verify-hostnames:
	@echo "$(BLUE)Verifying hostname resolution...$(NC)"
	@echo ""
	@echo "Testing mDNS hostname resolution:"
	@echo ""
	@for hostname in tenfive-runner.local tenseven-runner.local tensix-runner.local teneight-runner.local tennine-runner.local tenten-runner.local; do \
		echo "  Checking $$hostname..."; \
		if ping -c 1 -W 2 $$hostname >/dev/null 2>&1; then \
			IP=$$(ping -c 1 -W 2 $$hostname 2>/dev/null | head -1 | grep -oE '\([^)]+\)' | tr -d '()'); \
			echo "    $(GREEN)✓ Resolves to $$IP$(NC)"; \
		else \
			echo "    $(YELLOW)⚠ Cannot reach (mDNS may not be available)$(NC)"; \
			echo "    Add to /etc/hosts as fallback"; \
		fi; \
	done
	@echo ""

# ============================================================================
# UTILITY TARGETS
# ============================================================================

check-env:
	@if [ ! -f .env ]; then \
		echo "$(RED)Error: .env file not found$(NC)"; \
		echo "Run: $(GREEN)make setup$(NC)"; \
		exit 1; \
	fi
	@TENFIVE=$$(grep "^RUNNER_TOKEN_TENFIVE=" .env | cut -d= -f2); \
	TENSEVEN=$$(grep "^RUNNER_TOKEN_TENSEVEN=" .env | cut -d= -f2); \
	if [ -z "$$TENFIVE" ] || [ "$$TENFIVE" = "" ]; then \
		echo "$(RED)Error: RUNNER_TOKEN_TENFIVE is empty in .env$(NC)"; \
		exit 1; \
	fi; \
	if [ -z "$$TENSEVEN" ] || [ "$$TENSEVEN" = "" ]; then \
		echo "$(RED)Error: RUNNER_TOKEN_TENSEVEN is empty in .env$(NC)"; \
		exit 1; \
	fi; \
	echo "$(GREEN)✓ .env validation passed$(NC)"

# ============================================================================
# DOCUMENTATION
# ============================================================================

info:
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)     BlakePorts Docker Runners - Information$(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(GREEN)Active Runners:$(NC)"
	@for runner in $(ACTIVE_RUNNERS); do \
		echo "  • $$runner"; \
	done
	@echo ""
	@echo "$(GREEN)Available (Commented) Runners:$(NC)"
	@for runner in tensix-runner teneight-runner tennine-runner tenten-runner; do \
		echo "  • $$runner"; \
	done
	@echo ""
	@echo "$(GREEN)Token Generation:$(NC)"
	@echo "  Each runner requires its OWN token (single-use)"
	@echo "  Tokens expire after 1 hour if unused"
	@echo "  Run 'make tokens' to generate fresh tokens"
	@echo ""
	@echo "$(GREEN)Files:$(NC)"
	@echo "  • docker-compose.yml - Service definitions"
	@echo "  • .env - Configuration (gitignored)"
	@echo "  • example.env - Configuration template"
	@echo "  • Dockerfile - Runner image"
	@echo "  • entrypoint.sh - Container startup script"
	@echo "  • ssh_keys/ - SSH authentication"
	@echo ""
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
