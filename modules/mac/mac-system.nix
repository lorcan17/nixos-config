{ ... }:
{
  system.stateVersion = 5; # nix-darwin state version — don't change after first switch

  system.defaults = {
    dock = {
      autohide               = true;
      show-recents           = false;
      minimize-to-application = true;
      tilesize               = 48;
    };

    finder = {
      AppleShowAllExtensions      = true;
      FXEnableExtensionChangeWarning = false;
      ShowPathbar                 = true;
      ShowStatusBar               = true;
      _FXShowPosixPathInTitle     = true;
    };

    NSGlobalDomain = {
      AppleShowScrollBars      = "Always";
      AppleInterfaceStyle      = "Dark";
      AppleICUForce24HourTime  = true;
    };

    screencapture.location = "~/Desktop/Screenshots";

    trackpad = {
      Clicking             = true; # tap to click
      TrackpadThreeFingerDrag = true;
    };
  };

  networking.computerName = "lorcans-mac";
  networking.hostName     = "lorcans-mac";

  # Set iTerm2 font to JetBrainsMono Nerd Font so eza/starship icons render correctly.
  # iTerm2 doesn't honour system.defaults — we write the plist directly at activation.
  system.activationScripts.iterm2Font.text = ''
    defaults write com.googlecode.iterm2 "Normal Font" -string "JetBrainsMonoNerdFontMono-Regular 13"
    defaults write com.googlecode.iterm2 "Non Ascii Font" -string "JetBrainsMonoNerdFontMono-Regular 13"
  '';
}
