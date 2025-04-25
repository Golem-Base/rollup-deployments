{ inputs, self, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      treefmt-settings = {
        package = pkgs.treefmt;

        projectRootFile = "flake.nix";

        programs.deadnix.enable = true;
        programs.nixfmt.enable = true;

        programs.shellcheck.enable = true;
        programs.shfmt.enable = true;

        programs.yamlfmt.enable = true;

        settings.formatter.deadnix.pipeline = "nix";
        settings.formatter.deadnix.priority = 1;
        settings.formatter.nixfmt.pipeline = "nix";
        settings.formatter.nixfmt.priority = 2;

        settings.formatter.shellcheck.pipeline = "shell";
        settings.formatter.shellcheck.includes = [
          "*.sh"
          "*.bash"
          "*.envrc"
          "*.envrc.*"
          "bin/*"
        ];
        settings.formatter.shellcheck.priority = 1;
        settings.formatter.shfmt.pipeline = "shell";
        settings.formatter.shfmt.includes = [
          "*.sh"
          "*.bash"
          "*.envrc"
          "*.envrc.*"
          "bin/*"
        ];
        settings.formatter.shfmt.priority = 2;

        settings.formatter.yamlfmt.pipeline = "yaml";
        settings.formatter.yamlfmt.priority = 1;
      };

      formatter = inputs.treefmt-nix.lib.mkWrapper pkgs treefmt-settings;

      check =
        pkgs.runCommand "format-check"
          {
            nativeBuildInputs = [
              formatter
              pkgs.git
            ];

            # only check on Linux
            meta.platforms = pkgs.lib.platforms.linux;
          }
          ''
            export HOME=$NIX_BUILD_TOP/home

            # keep timestamps so that treefmt is able to detect mtime changes
            cp --no-preserve=mode --preserve=timestamps -r ${self} source
            cd source
            git init --quiet
            git add .
            treefmt --no-cache
            if ! git diff --exit-code; then
              echo "-------------------------------"
              echo "aborting due to above changes ^"
              exit 1
            fi
            touch $out
          '';
    in
    {
      formatter = formatter // {
        meta = formatter.meta // {
          tests = { inherit check; };
        };
      };
    };
}
