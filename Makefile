.PHONY: test format lint check setup-plenary

# Clone plenary.nvim to /tmp if it's not already there (for `make test`).
setup-plenary:
	@if [ ! -d "/tmp/plenary.nvim" ]; then \
		echo "Cloning plenary.nvim to /tmp/plenary.nvim..."; \
		git clone --depth=1 https://github.com/nvim-lua/plenary.nvim /tmp/plenary.nvim; \
	fi

# Run the test suite with plenary.
test: setup-plenary
	@PLENARY_DIR=$${PLENARY_DIR:-/tmp/plenary.nvim} nvim --headless --noplugin \
		-u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/spec { minimal_init = 'tests/minimal_init.lua' }"

# Format with stylua.
format:
	@stylua lua/ plugin/ tests/

# Lint with selene (if installed).
lint:
	@if command -v selene >/dev/null 2>&1; then \
		selene lua/ plugin/; \
	else \
		echo "selene not found, skipping"; \
	fi

# Run everything.
check: format lint test
