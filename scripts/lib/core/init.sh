#!/usr/bin/env bash

# shellcheck source=scripts/lib/core/env.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/env.sh"
# shellcheck source=scripts/lib/core/output.sh
source "$J3W1ZSH_REPO_ROOT/scripts/lib/core/output.sh"
# shellcheck source=scripts/lib/core/platform.sh
source "$J3W1ZSH_REPO_ROOT/scripts/lib/core/platform.sh"
# shellcheck source=scripts/lib/core/state.sh
source "$J3W1ZSH_REPO_ROOT/scripts/lib/core/state.sh"
# shellcheck source=scripts/lib/core/filesystem.sh
source "$J3W1ZSH_REPO_ROOT/scripts/lib/core/filesystem.sh"
# shellcheck source=scripts/lib/core/neovim.sh
source "$J3W1ZSH_REPO_ROOT/scripts/lib/core/neovim.sh"

j3w1zsh_output_init
