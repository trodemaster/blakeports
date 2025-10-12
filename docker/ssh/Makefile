# SSH Legacy Proxy - Makefile
# Quick commands for managing the SSH proxy container

.PHONY: help build up down restart logs shell test clean setup

help: ## Show this help message
	@echo 'SSH Legacy Proxy - Available Commands:'
	@echo ''
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ''

setup: ## Run interactive setup
	@./setup.sh

build: ## Build the Docker image
	@echo "Building SSH proxy container..."
	@docker compose build

up: ## Start the SSH proxy in background
	@echo "Starting SSH proxy..."
	@docker compose up -d
	@echo "✅ SSH proxy is running on port 2222"
	@echo ""
	@echo "Test connection: ssh -p 2222 sshproxy@localhost"

down: ## Stop the SSH proxy
	@echo "Stopping SSH proxy..."
	@docker compose down
	@echo "✅ SSH proxy stopped"

restart: down up ## Restart the SSH proxy

logs: ## Show container logs (follow mode)
	@docker compose logs -f

logs-tail: ## Show last 50 lines of logs
	@docker compose logs --tail=50

shell: ## Open shell in running container
	@docker compose exec ssh-proxy bash

ps: ## Show container status
	@docker compose ps

test: ## Test SSH proxy connection
	@echo "Testing SSH proxy connection..."
	@ssh -p 2222 -o ConnectTimeout=5 -o StrictHostKeyChecking=no sshproxy@localhost exit && \
		echo "✅ SSH proxy is accepting connections" || \
		echo "❌ SSH proxy connection failed"

test-legacy: ## Test connection to legacy system through proxy
	@echo "This will test the full proxy chain to tenseven.local"
	@ssh -o ProxyCommand="ssh -W %h:%p -p 2222 sshproxy@localhost" blake@tenseven.local exit && \
		echo "✅ Successfully connected to legacy system via proxy" || \
		echo "❌ Failed to connect to legacy system"

clean: down ## Stop container and remove volumes
	@echo "Cleaning up..."
	@docker compose down -v
	@echo "✅ Cleaned up containers and volumes"

clean-all: clean ## Clean everything including images
	@echo "Removing Docker images..."
	@docker compose down -v --rmi all
	@echo "✅ Cleaned up everything"

status: ## Show detailed status
	@echo "=== Container Status ==="
	@docker compose ps
	@echo ""
	@echo "=== Port Mappings ==="
	@docker compose port ssh-proxy 2222 2>/dev/null || echo "Container not running"
	@echo ""
	@echo "=== Health Check ==="
	@docker compose exec ssh-proxy bash -c "nc -z localhost 2222 && echo '✅ SSH listening on port 2222' || echo '❌ SSH not responding'" 2>/dev/null || echo "Container not running"

rebuild: ## Rebuild container from scratch
	@echo "Rebuilding SSH proxy..."
	@docker compose down
	@docker compose build --no-cache
	@docker compose up -d
	@echo "✅ Rebuild complete"

.DEFAULT_GOAL := help

