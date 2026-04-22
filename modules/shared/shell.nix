{ pkgs, lib, ... }:
{
  home-manager.users.lorcan = {
    programs.zsh = {
      enable                   = true;
      autosuggestion.enable    = true;
      syntaxHighlighting.enable = true;

      shellAliases = {
        # Better Unix defaults
        ll  = "eza -la --icons --git";
        lt  = "eza --tree --level=2 --icons";
        cat = "bat";

        # Nix rebuilds
        rebuild-mac    = "sudo darwin-rebuild switch --flake ~/nix-config#lorcans-mac";
        rebuild-server       = "ssh -t optiplex 'cd ~/nix-config && git pull && sudo nixos-rebuild switch --flake .#optiplex'";
        rebuild-server-hard  = "ssh -t optiplex 'cd ~/nix-config && git fetch origin && git reset --hard origin/main && sudo nixos-rebuild switch --flake .#optiplex'";
        nix-search     = "nix search nixpkgs";

        # Git
        g  = "git";
        lg = "lazygit";
        gp = "git push";
        gl = "git pull";

        # lululemon
        tf       = "terraform";
        dbt-run  = "dbt run --profiles-dir .";
        dbt-test = "dbt test --profiles-dir .";

        # Quick tools
        dq    = "duckdb";
        ports = "lsof -iTCP -sTCP:LISTEN -n -P";
        myip  = "curl -s ifconfig.me";
        install-claude-code = "claude update";
      };

      initContent = ''
        if [[ -f /run/agenix/fmp-api-key ]]; then
          export FMP_API_KEY=$(cat /run/agenix/fmp-api-key)
        fi

        or-claude() {
          local key_file="/run/agenix/open-router-api-key"
          if [[ ! -f "$key_file" ]]; then
            echo "or-claude: secret not found at $key_file" >&2
            return 1
          fi
          local n=$((RANDOM % 4))
          local model
          case $n in
            0) model="meta-llama/llama-3.3-70b-instruct:free" ;;
            1) model="qwen/qwen-2.5-72b-instruct:free" ;;
            2) model="deepseek/deepseek-r1:free" ;;
            3) model="google/gemma-3-12b-it:free" ;;
          esac
          echo "or-claude: $model"
          ANTHROPIC_BASE_URL="https://openrouter.ai/api/v1" \
          ANTHROPIC_API_KEY=$(cat "$key_file") \
          CLAUDE_CONFIG_DIR="$HOME/.claude-openrouter" \
          claude --model "$model" "$@"
        }

        eval "$(zoxide init zsh)"
        export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
      '';
    };

    programs.starship = {
      enable   = true;
      settings = {
        add_newline = false;
        character   = { success_symbol = "[›](bold green)"; error_symbol = "[›](bold red)"; };
        directory.truncation_length = 3;
        git_branch.symbol = " ";
        nix_shell.symbol  = " ";
        terraform.symbol  = "󱁢 ";
        python.symbol     = " ";
      };
    };

    programs.fzf    = { enable = true; enableZshIntegration = true; };
    programs.zoxide = { enable = true; enableZshIntegration = true; };

    # Auto-loads nix devshells per project when .envrc is present
    programs.direnv = { enable = true; nix-direnv.enable = true; };

    # Share global Claude config into the OpenRouter config dir so or-claude
    # has the same CLAUDE.md instructions and custom commands, but no credentials.
    home.activation.claudeOpenRouterConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p "$HOME/.claude-openrouter"
      $DRY_RUN_CMD ln -sf "$HOME/.claude/CLAUDE.md" "$HOME/.claude-openrouter/CLAUDE.md"
      $DRY_RUN_CMD ln -sf "$HOME/.claude/commands" "$HOME/.claude-openrouter/commands"
      $DRY_RUN_CMD ln -sf "$HOME/.claude/settings.json" "$HOME/.claude-openrouter/settings.json"
    '';
  };
}
