{
  description = "Flake providing the Lem text editor";

  inputs = {
    nixpkgs.url = "github:NixOs/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    treefmt.url = "github:numtide/treefmt-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
      flake-parts,
      treefmt,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; }

      {
        systems = import systems;
        imports = [ treefmt.flakeModule ];
        perSystem =
          { self', pkgs, ... }:
          {
            treefmt = {
              projectRootFile = "flake.nix";
              programs.nixfmt.enable = true;
            };

            packages = rec {
              cl-charms = pkgs.sbclPackages.cl-charms.overrideLispAttrs (oldAttrs: {
                nativeLibs = [ pkgs.ncurses ];
              });
              jsonrpc = pkgs.sbclPackages.jsonrpc.overrideLispAttrs (oldAttrs: {
                src = pkgs.fetchFromGitHub {
                  owner = "cxxxr";
                  repo = "jsonrpc";
                  rev = "6e3d23f9bec1af1a3155c21cc05dad9d856754bc";
                  hash = "sha256-QbXesQbHHrDtcV2D4FTnKMacEYZJb2mRBIMC7hZM/A8=";
                };
                systems = [
                  "jsonrpc"
                  "jsonrpc/transport/stdio"
                  "jsonrpc/transport/tcp"
                ];
                lispLibs =
                  with pkgs.sbclPackages;
                  oldAttrs.lispLibs
                  ++ [
                    cl_plus_ssl
                    quri
                    fast-io
                    trivial-utf-8
                  ];
              });
              queues = pkgs.sbclPackages.queues.overrideLispAttrs (oldAttrs: {
                systems = [
                  "queues"
                  "queues.priority-cqueue"
                  "queues.priority-queue"
                  "queues.simple-cqueue"
                  "queues.simple-queue"
                ];
                lispLibs = oldAttrs.lispLibs ++ (with pkgs.sbclPackages; [ bordeaux-threads ]);
              });
              micros = pkgs.sbcl.buildASDFSystem {
                pname = "micros";
                version = "unstable-2024-05-15";
                src = pkgs.fetchFromGitHub {
                  owner = "lem-project";
                  repo = "micros";
                  rev = "f80d7772ca76e9184d9bc96bc227147b429b11ed";
                  hash = "sha256-RiBHxKWVZsB4JPktLSVcup7WIUMk08VbxU1zeBfGrFQ=";
                };
                patches = [ ./micros.patch ];
              };

              lem-mailbox = pkgs.sbcl.buildASDFSystem {
                pname = "lem-mailbox";
                version = "unstable-2023-09-10";
                src = pkgs.fetchFromGitHub {
                  owner = "lem-project";
                  repo = "lem-mailbox";
                  rev = "12d629541da440fadf771b0225a051ae65fa342a";
                  hash = "sha256-hb6GSWA7vUuvSSPSmfZ80aBuvSVyg74qveoCPRP2CeI=";
                };
                lispLibs = with pkgs.sbcl.pkgs; [
                  bordeaux-threads
                  bt-semaphore
                  queues
                ];
              };

              lem-base16-themes = pkgs.sbcl.buildASDFSystem {
                pname = "lem-base16-themes";
                version = "unstable-2023-07-04";
                src = pkgs.fetchFromGitHub {
                  owner = "lem-project";
                  repo = "lem-base16-themes";
                  rev = "07dacae6c1807beaeffc730063b54487d5c82eb0";
                  hash = "sha256-UoVJfY2v4+Oc1MfJ9+4iT2ZwIzUEYs4jRi2Xu69nGkM=";
                };
                lispLibs = [ lem_without_frontend ];
              };

              lem_without_frontend =
                (pkgs.callPackage ./default.nix {
                  inherit cl-charms jsonrpc queues;
                  micros = self.packages.x86_64-linux.micros;
                  lem-mailbox = self.packages.x86_64-linux.lem-mailbox;
                  lem = self.packages.x86_64-linux.lem;
                })
                // {
                  withFrontend =
                    {
                      frontend,
                      extraLispLibs ? [ ],
                      extraNativeLibs ? [ ],
                    }:
                    pkgs.wrapLisp {
                      faslExt = "fasl";
                      pkg = pkgs.sbcl.buildASDFSystem {
                        inherit (self'.packages.lem_without_frontend) src version;
                        pname = "lem-${frontend}";
                        meta.mainProgram = "lem";
                        lispLibs =
                          (with self'.packages; [
                            lem_without_frontend
                            lem-base16-themes
                            jsonrpc
                            cl-charms
                          ])
                          ++ (with pkgs.sbcl.pkgs; [
                            _3bmd
                            _3bmd-ext-code-blocks
                            lisp-preprocessor
                            trivial-ws
                            trivial-open-browser
                          ])
                          ++ extraLispLibs;
                        nativeLibs = extraNativeLibs;
                        nativeBuildInputs = with pkgs; [
                          openssl
                          makeWrapper
                        ];
                        buildScript = pkgs.writeText "build-lem.lisp" ''
                          (load (concatenate 'string (sb-ext:posix-getenv "asdfFasl") "/asdf.fasl"))
                          ; Uncomment this line to load the :lem-tetris contrib system
                          ; (asdf:load-system :lem-tetris)
                          (asdf:load-system :lem-${frontend})
                          (sb-ext:save-lisp-and-die
                            "lem"
                            :executable t
                            :purify t
                            #+sb-core-compression :compression
                            #+sb-core-compression t
                            :toplevel #'lem:main)
                        '';
                        patches = [ ./fix-quickload.patch ];
                        installPhase = ''
                          mkdir -p $out/bin
                          cp -v lem $out/bin
                          wrapProgram $out/bin/lem \
                            --prefix LD_LIBRARY_PATH : $LD_LIBRARY_PATH \
                        '';
                      };
                    };
                };
              lem-ncurses = lem_without_frontend.withFrontend {
                frontend = "ncurses";
              };
              lem-sdl2 = lem_without_frontend.withFrontend {
                frontend = "sdl2";
                extraLispLibs = with pkgs.sbcl.pkgs; [
                  sdl2
                  sdl2-ttf
                  sdl2-image
                  trivial-main-thread
                ];
                extraNativeLibs = with pkgs; [
                  SDL2
                  SDL2_ttf
                  SDL2_image
                ];
              };
              default = lem-ncurses;
              lem-withPackages-check = lem-sdl2.withPackages (p: [
                p.duologue
              ]);
            };

            devShells.default =
              let
                sbcl' = pkgs.sbcl.withPackages (ps: with ps; [ cl-cram ]);
              in
              pkgs.mkShell {
                LD_LIBRARY_PATH =
                  with pkgs;
                  lib.makeLibraryPath [
                    openssl
                    ncurses
                    libffi
                    SDL2
                    SDL2_ttf
                    SDL2_image
                    tree-sitter-grammars.tree-sitter-c
                  ];
                buildInputs = with pkgs; [
                  openssl
                  ncurses
                  roswell
                  SDL2
                  SDL2_ttf
                  SDL2_image
                  pkg-config
                  libffi
                  tree-sitter-grammars.tree-sitter-c
                  sbcl'
                ];
              };
          };
      };
}
