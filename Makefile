PREFIX    ?= /usr/local
BINDIR    := $(PREFIX)/bin
LIBDIR    := $(PREFIX)/lib/batch-dl
CONFDIR   := $(PREFIX)/etc/batch-dl

SCRIPTS   := batch-dl batch-rename
LIBS      := lib/logging.sh lib/validation.sh lib/download.sh lib/rename.sh

.PHONY: help install uninstall lint test check

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

install: ## Install scripts to $(PREFIX)/bin
	@echo "Installing to $(BINDIR)..."
	install -d $(BINDIR) $(LIBDIR)
	install -m 755 $(SCRIPTS) $(BINDIR)/
	install -m 644 $(LIBS) $(LIBDIR)/
	@# Patch library paths in installed scripts
	@for s in $(SCRIPTS); do \
		sed -i 's|SCRIPT_DIR=.*|SCRIPT_DIR="$(LIBDIR)"|' $(BINDIR)/$$s; \
	done
	@echo "Done. Run 'batch-dl --help' to get started."

uninstall: ## Remove installed files
	rm -f $(addprefix $(BINDIR)/, $(SCRIPTS))
	rm -rf $(LIBDIR)
	@echo "Uninstalled."

lint: ## Run shellcheck on all scripts
	shellcheck -s bash $(SCRIPTS) $(LIBS)

test: ## Run test suite
	@echo "Running tests..."
	@bash tests/run_tests.sh

check: lint test ## Run lint + tests
