
{
  description = "nirinit";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs:
    let
      inherit (inputs.nixpkgs) lib;
      inherit (inputs) self;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      eachSystem = f:
        lib.genAttrs systems (
          system: f inputs.nixpkgs.legacyPackages.${system}
        );

      # Shared nirinit options for NixOS and Home Manager.
      mkNirinitOptions = pkgs: {
        services.nirinit = {
          enable = lib.mkEnableOption "Nirinit";

          package = lib.mkPackageOption
            self.packages.${pkgs.stdenv.hostPlatform.system}
            "nirinit"
            { };

          settings = lib.mkOption {
            type = lib.types.submodule {
              freeformType = (pkgs.formats.toml { }).type;

              options = {
                skip = lib.mkOption {
                  type = lib.types.submodule {
                    options = {
                      apps = lib.mkOption {
                        type = lib.types.listOf lib.types.str;
                        default = [ ];
                        description = "List of app IDs to skip during session restore";
                      };
                    };
                  };

                  default = { };
                  description = "Applications to skip";
                };

                launch = lib.mkOption {
                  type = lib.types.attrsOf lib.types.str;
                  default = { };
                  description = "Map app_id to actual launch command";
                };
              };
            };

            default = { };
            description = "Configuration for nirinit";
          };
        };
      };

      # Shared TOML configuration generation.
      mkNirinitConfig = pkgs: cfg:
        (pkgs.formats.toml { }).generate
          "nirinit-config.toml"
          cfg.settings;

    in
    {
      # NixOS module.
      nixosModules = {
        nirinit = { config, pkgs, ... }:
          let
            cfg = config.services.nirinit;
            configFile = mkNirinitConfig pkgs cfg;
          in
          {
            options = mkNirinitOptions pkgs;

            config = lib.mkIf cfg.enable {
              systemd.user.services.nirinit = {
                enable = true;
                description = "Nirinit";

                wantedBy = [
                  "graphical-session.target"
                ];

                partOf = [
                  "graphical-session.target"
                ];

                wants = [
                  "graphical-session.target"
                ];

                after = [
                  "graphical-session.target"
                ];

                serviceConfig = {
                  Type = "simple";
                  Restart = "always";

                  ExecStart =
                    "${lib.getExe' cfg.package "nirinit"} --config ${configFile}";

                  PrivateTmp = true;
                };
              };
            };
          };

        default = self.nixosModules.nirinit;
      };

      # Native Home Manager module.
      homeManagerModules = {
        nirinit = { config, pkgs, ... }:
          let
            cfg = config.services.nirinit;
            configFile = mkNirinitConfig pkgs cfg;
          in
          {
            options = mkNirinitOptions pkgs;

            config = lib.mkIf cfg.enable {
              systemd.user.services.nirinit = {
                Unit = {
                  Description = "Nirinit";

                  Wants = [
                    "graphical-session.target"
                  ];

                  PartOf = [
                    "graphical-session.target"
                  ];

                  After = [
                    "graphical-session.target"
                  ];
                };

                Service = {
                  Type = "simple";
                  Restart = "always";

                  ExecStart =
                    "${lib.getExe' cfg.package "nirinit"} --config ${configFile}";

                  PrivateTmp = true;
                };

                Install = {
                  WantedBy = [
                    "graphical-session.target"
                  ];
                };
              };
            };
          };

        default = self.homeManagerModules.nirinit;
      };

      # Packages.
      packages = eachSystem (
        pkgs:
        let
          packageName = "nirinit";

          mkNirinit =
            rustPlatform:
            rustPlatform.buildRustPackage {
              pname = packageName;
              src = ./.;
              version = "0.3.1";

              cargoLock.lockFile = ./Cargo.lock;

              stripAllList = [ "bin" ];

              meta.mainProgram = packageName;
            };

        in
        {
          nirinit = mkNirinit pkgs.rustPlatform;

          static = mkNirinit pkgs.pkgsStatic.rustPlatform;

          default =
            self.packages.${pkgs.stdenv.hostPlatform.system}.nirinit;
        }
      );

      # Development shell.
      devShells = eachSystem (
        pkgs:
        let
          fenixPkgs =
            inputs.fenix.packages.${pkgs.stdenv.hostPlatform.system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.nixfmt

              (fenixPkgs.complete.withComponents [
                "cargo"
                "clippy"
                "rust-src"
                "rustc"
                "rustfmt"
                "rust-analyzer"
              ])
            ];
          };
        }
      );
    };
}
