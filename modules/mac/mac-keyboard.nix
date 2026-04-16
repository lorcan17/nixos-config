{ ... }:
{
  system.defaults.NSGlobalDomain = {
    # Fast key repeat — essential for Vim-style navigation
    InitialKeyRepeat        = 12;    # shortest delay before repeat starts
    KeyRepeat               = 1;     # fastest repeat rate (~15ms)
    ApplePressAndHoldEnabled = false; # disable accent popup, enable repeat

    # Tab through all controls in dialogs, not just text fields
    AppleKeyboardUIMode = 3;

    # Disable autocorrect — gets in the way when typing code
    NSAutomaticSpellingCorrectionEnabled = false;
    NSAutomaticCapitalizationEnabled     = false;
    NSAutomaticPeriodSubstitutionEnabled = false;
  };
}
