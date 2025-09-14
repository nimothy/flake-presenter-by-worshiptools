{
  description = "WorshipTools Presenter (AppImage) wrapper for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

  outputs =
    { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems =
        f:
        builtins.listToAttrs (
          map (system: {
            name = system;
            value = f system;
          }) systems
        );
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
            };
          };
        in
        {
          presenter = pkgs.callPackage (
            {
              lib,
              appimageTools,
              fetchurl,
            }:
            let
              pname = "presenter";
              version = "2025.1.1";
              src = fetchurl {
                url = "https://download.worshiptools.com/download/latest/linux";
                hash = "sha256-OA2JCa+j9//PRAM+HVr51ivbyeTql9i3h4b2ze95ObA=";
              };
              contents = appimageTools.extractType2 { inherit pname version src; };
            in
            appimageTools.wrapType2 {
              inherit pname version src;

              # Add common runtime libs (extend if you hit missing .so errors)
              extraPkgs =
                p: with p; [
                  libglvnd
                  fontconfig
                  freetype
                  libxkbcommon
                  alsa-lib
                ];

              extraInstallCommands = ''
                # Desktop file -> fix Exec to call the wrapper
                if ls ${contents}/*.desktop >/dev/null 2>&1; then
                  install -Dm444 ${contents}/*.desktop $out/share/applications/${pname}.desktop
                  substituteInPlace $out/share/applications/${pname}.desktop \
                    --replace-fail "Exec=AppRun" "Exec=${pname}"
                fi

                # Icons (if shipped)
                if ls ${contents}/usr/share/icons/hicolor/*/apps/* >/dev/null 2>&1; then
                  cp -r ${contents}/usr/share/icons $out/share/
                fi
              '';

              meta = with lib; {
                description = "Presenter by WorshipTools (AppImage wrapper)";
                homepage = "https://www.worshiptools.com/en-us/presenter/download";
                license = licenses.unfree;
                platforms = [ "x86_64-linux" ];
                mainProgram = "presenter";
              };
            }
          ) { };
        }
      );

      # Let `nix run .` (and `nix run .#presenter`) work
      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.presenter}/bin/presenter";
        };
        presenter = {
          type = "app";
          program = "${self.packages.${system}.presenter}/bin/presenter";
        };
      });

      formatter = forAllSystems (system: (import nixpkgs { inherit system; }).nixpkgs-fmt);

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nixpkgs-fmt
              statix
              deadnix
              curl
            ];
          };
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          presenter = self.packages.${system}.presenter;
        in
        {
          build = presenter;

          bin-exists = pkgs.runCommand "presenter-bin-exists" { } ''
            test -x ${presenter}/bin/presenter
            mkdir -p $out && touch $out/ok
          '';

          maybe-desktop = pkgs.runCommand "presenter-maybe-desktop" { } ''
            if [ -f ${presenter}/share/applications/presenter.desktop ]; then
              grep -q '^Exec=presenter' ${presenter}/share/applications/presenter.desktop
            fi
            mkdir -p $out && touch $out/ok
          '';

          maybe-icons = pkgs.runCommand "presenter-maybe-icons" { } ''
            if [ -d ${presenter}/share/icons ]; then
              find ${presenter}/share/icons -type f | head -n1 >/dev/null
            fi
            mkdir -p $out && touch $out/ok
          '';

          statix =
            pkgs.runCommand "statix"
              {
                src = ./.;
                nativeBuildInputs = [ pkgs.statix ];
              }
              ''
                cd $src
                statix check
                mkdir -p $out && touch $out/ok
              '';

          deadnix =
            pkgs.runCommand "deadnix"
              {
                src = ./.;
                nativeBuildInputs = [ pkgs.deadnix ];
              }
              ''
                cd $src
                deadnix --fail
                mkdir -p $out && touch $out/ok
              '';
        }
      );

      defaultPackage = forAllSystems (system: self.packages.${system}.presenter);
    };
}
