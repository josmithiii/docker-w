IMAGE = claude-latex

.PHONY: help build rebuild run clean status

.DEFAULT_GOAL := help

build: ## Build image (uses cache)
	docker build -t $(IMAGE) .

rebuild: ## Build image from scratch (no cache)
	docker build --no-cache -t $(IMAGE) .

run: build ## Build if needed, then run interactive session
	./run.sh

clean: ## Remove image and dangling layers
	-docker rmi $(IMAGE)
	-docker image prune -f

status: ## Show image info and running containers
	@docker image inspect $(IMAGE) --format '{{.Id}} {{.Created}}' 2>/dev/null \
		|| echo "Image '$(IMAGE)' not built"
	@docker ps --filter ancestor=$(IMAGE) --format 'Running: {{.ID}} {{.Status}}' 2>/dev/null

help: ## Show this help
	@grep -E '^[a-z][a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) \
		| awk -F ':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'
	@echo ''
	@echo 'Run with a specific project:'
	@echo '  ./run.sh --workdir /w/pasp'
	@echo '  ./run.sh --workdir /l/l420'
