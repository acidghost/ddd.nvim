set shell := ["bash", "-euo", "pipefail", "-c"]

format:
    stylua lua plugin tests

format-check:
    stylua --check lua plugin tests

lint:
    VIMRUNTIME="$(NVIM_LOG_FILE=/dev/null nvim --headless -u NONE -i NONE \
        --cmd 'lua io.write(vim.env.VIMRUNTIME)' \
        --cmd 'qa!')" \
        lua-language-server --check=. --check_format=pretty --checklevel=Warning

test:
    NVIM_LOG_FILE=/dev/null nvim --headless -u NONE \
        --cmd 'set runtimepath^=.' \
        --cmd 'runtime plugin/ddd.lua' \
        -l tests/smoke.lua

check: format-check lint test
