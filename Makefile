SHELL := /usr/bin/env bash

PROJECT := BelTu-Agent.sh
TEST := tests/test_beltu.sh
LOCAL_BIN := $(HOME)/.local/bin
GLOBAL_BIN := /usr/local/bin
COMMAND := beltu
PROJECT_ABS := $(CURDIR)/$(PROJECT)

.PHONY: check test install-local install uninstall-local uninstall doctor

check:
	@bash -n "$(PROJECT)"
	@chmod 0755 "$(PROJECT)" "$(TEST)"
	@echo "Syntax check: OK"

test: check
	@"./$(TEST)"

install-local: check
	@mkdir -p "$(LOCAL_BIN)"
	@chmod 0755 "$(PROJECT)"
	@printf '%s\n' '#!/usr/bin/env bash' 'exec /usr/bin/env bash "$(PROJECT_ABS)" "$$@"' > "$(LOCAL_BIN)/$(COMMAND)"
	@chmod 0755 "$(LOCAL_BIN)/$(COMMAND)"
	@echo "Installed user-local command: $(LOCAL_BIN)/$(COMMAND)"
	@if [[ ":$${PATH}:" != *":$(LOCAL_BIN):"* ]]; then \
		echo "PATH notice: $(LOCAL_BIN) is not currently in PATH."; \
		echo 'Run: export PATH="$$HOME/.local/bin:$$PATH"'; \
		echo 'Then run: hash -r'; \
	fi

install: check
	@tmp="$$(mktemp)"; \
	trap 'rm -f "$$tmp"' EXIT; \
	printf '%s\n' '#!/usr/bin/env bash' 'exec /usr/bin/env bash "$(PROJECT_ABS)" "$$@"' > "$$tmp"; \
	chmod 0755 "$$tmp"; \
	if [[ "$$EUID" -eq 0 ]]; then \
		install -m 0755 "$$tmp" "$(GLOBAL_BIN)/$(COMMAND)"; \
	else \
		command -v sudo >/dev/null 2>&1 || { echo "sudo is required for system-wide installation." >&2; exit 1; }; \
		sudo install -m 0755 "$$tmp" "$(GLOBAL_BIN)/$(COMMAND)"; \
	fi; \
	echo "Installed system-wide command: $(GLOBAL_BIN)/$(COMMAND)"

uninstall-local:
	@rm -f "$(LOCAL_BIN)/$(COMMAND)"
	@echo "Removed user-local command: $(LOCAL_BIN)/$(COMMAND)"

uninstall:
	@if [[ "$$EUID" -eq 0 ]]; then \
		rm -f "$(GLOBAL_BIN)/$(COMMAND)"; \
	else \
		command -v sudo >/dev/null 2>&1 || { echo "sudo is required for system-wide uninstall." >&2; exit 1; }; \
		sudo rm -f "$(GLOBAL_BIN)/$(COMMAND)"; \
	fi
	@echo "Removed system-wide command: $(GLOBAL_BIN)/$(COMMAND)"

doctor:
	@echo "BelTu-Agent entrypoint diagnostics"
	@echo "Project script: $$(pwd)/$(PROJECT)"
	@echo "Project tool bin: $$(pwd)/.beltu-tools/bin"
	@echo "Project cargo bin: $$(pwd)/.beltu-tools/cargo/bin"
	@ls -l "$(PROJECT)"
	@command -v bash
	@bash --version | sed -n '1p'
	@bash -n "$(PROJECT)"
	@echo "Script syntax: OK"
	@if command -v beltu >/dev/null 2>&1; then \
		echo "beltu: $$(command -v beltu)"; \
		beltu --version; \
	else \
		echo "beltu: not found in PATH"; \
	fi
