{
  lib,
  inputs ? { },
  ...
}:

{
  # Import the shared default devshell module
  imports = [
    # Prefer using the flake input when available (e.g., during nix develop or system switch)
    # This avoids "missing path" errors caused by nested git repositories.
    (
      if inputs ? nix-devshells then
        inputs.nix-devshells.devenvModules.default
      else
        ./nix-devshells/shells/default/default.nix
    )
  ];

  # Devenv root must be absolute for many features to work correctly
  devenv.root = lib.mkDefault "/home/martin/Develop/github.com/kleinbem/nix";

  # Pass along the flake inputs to imported modules
  _module.args.inputs = inputs;

  # --- Advanced Features ---

  # Processes (Unlocks "devenv up")
  # This makes services discoverable and manageable via the devenv CLI.
  # You can add your AI services here to have them managed by devenv.
  processes.workspace-info.exec = "while true; do date; sleep 3600; done";

  # Scripts (Custom CLI commands for your workspace)
  scripts.workspace-status.exec = ''
    echo "🏗️  Project Root: /home/martin/Develop/github.com/kleinbem/nix"
    echo -n "🚀 Status: "
    pushd /home/martin/Develop/github.com/kleinbem/nix > /dev/null
    devenv tasks run workspace:health
    popd > /dev/null
  '';

  # Tasks (Run things before entering the shell or on demand)
  tasks."workspace:health" = {
    exec = ''
      # Check if Ollama is reachable
      if curl -s -f http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo "✅ Ollama is ONLINE"
      else
        echo "⚠️ Ollama is OFFLINE (Run 'just ai-up' to start)"
      fi
    '';
    before = [ "devenv:enterShell" ];
  };
}
