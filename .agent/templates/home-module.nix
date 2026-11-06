{ pkgs, ... }:

{
  programs.example = {
    enable = true;
    # Custom settings
  };

  # Home packages
  home.packages = with pkgs; [
    # User-specific tools
  ];

  # Environment variables
  home.sessionVariables = {
    # EDITOR = "vim";
  };
}
