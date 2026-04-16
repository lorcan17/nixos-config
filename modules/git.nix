{ pkgs, ... }:
{
  home-manager.users.lorcan = {
    # delta is now a separate top-level program, not nested under git
    programs.delta = {
      enable               = true;
      enableGitIntegration = true;
      options = { navigate = true; side-by-side = true; line-numbers = true; };
    };

    programs.git = {
      enable  = true;
      ignores = [ ".DS_Store" "*.swp" ".env" ".direnv" "__pycache__" ];

      # Explicitly null — we're not using GPG/SSH commit signing
      signing.format = null;

      # All git config now lives under settings (replaces userName, userEmail, extraConfig, aliases)
      settings = {
        user.name  = "Lorcan";
        user.email = "ltravers92@gmail.com";

        init.defaultBranch   = "main";
        push.autoSetupRemote = true;
        pull.rebase          = true;
        core.editor          = "nvim";
        merge.conflictstyle  = "zdiff3";
        diff.algorithm       = "histogram";
        rerere.enabled       = true;

        alias = {
          lg      = "log --oneline --graph --decorate -20";
          st      = "status -sb";
          co      = "checkout";
          br      = "branch";
          cm      = "commit -m";
          amend   = "commit --amend --no-edit";
          unstage = "reset HEAD --";
          last    = "log -1 HEAD --stat";
        };
      };
    };

    programs.lazygit = {
      enable   = true;
      settings = { gui.theme.lightTheme = false; };
    };
  };
}
