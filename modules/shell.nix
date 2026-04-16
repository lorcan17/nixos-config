{ pkgs, ... }:
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
        rebuild-server = "ssh optiplex 'cd ~/nix-config && git pull && sudo nixos-rebuild switch --flake .#optiplex'";
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
  };
}
