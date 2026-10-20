{
  description = "treasury — a business-banking core in Haskell (demo)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/7fd4004d0511991fff3a0524856a9be09e28c5f0";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f nixpkgs.legacyPackages.${system});
      ghcVersion = "ghc910";
      localPackages = [ "treasury-core" "treasury-partner-client" "treasury-api" "treasury-workers" ];
      hsPkgsFor = pkgs:
        pkgs.haskell.packages.${ghcVersion}.override {
          overrides = hself: hsuper:
            # Test suites need a live Postgres and run in CI via cabal; the
            # sandboxed nix build only produces the binaries.
            nixpkgs.lib.genAttrs localPackages
              (name: pkgs.haskell.lib.dontCheck (hself.callCabal2nix name (./. + "/${name}") { }));
        };
    in
    {
      packages = forAllSystems (pkgs:
        let hsPkgs = hsPkgsFor pkgs;
        in nixpkgs.lib.genAttrs localPackages (name: hsPkgs.${name}) // {
          default = hsPkgs.treasury-api;
        });

      devShells = forAllSystems (pkgs:
        let
          hsPkgs = hsPkgsFor pkgs;
          pgStart = pkgs.writeShellScriptBin "pg-start" ''
            set -euo pipefail
            export PGDATA="''${PGDATA:-$PWD/.pg/data}"
            export PGHOST="''${PGHOST:-$PWD/.pg}"
            mkdir -p "$PGHOST"
            if [ ! -d "$PGDATA" ]; then
              initdb --auth=trust --username=treasury --no-locale --encoding=UTF8 "$PGDATA" >/dev/null
              echo "unix_socket_directories = '$PGHOST'" >> "$PGDATA/postgresql.conf"
              echo "listen_addresses = 'localhost'" >> "$PGDATA/postgresql.conf"
              echo "port = 5433" >> "$PGDATA/postgresql.conf"
            fi
            if ! pg_ctl -D "$PGDATA" status >/dev/null 2>&1; then
              pg_ctl -D "$PGDATA" -l "$PGHOST/postgres.log" start >/dev/null
            fi
            for db in treasury treasury_test; do
              psql -h localhost -p 5433 -U treasury -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = '$db'" | grep -q 1 \
                || createdb -h localhost -p 5433 -U treasury "$db"
            done
            echo "postgres ready on localhost:5433 (databases: treasury, treasury_test)"
          '';
          pgStop = pkgs.writeShellScriptBin "pg-stop" ''
            pg_ctl -D "''${PGDATA:-$PWD/.pg/data}" stop
          '';
        in
        {
          default = hsPkgs.shellFor {
            packages = p: map (name: p.${name}) localPackages;
            withHoogle = false;
            nativeBuildInputs = [
              hsPkgs.cabal-install
              hsPkgs.hspec-discover
              pkgs.ormolu
              pkgs.hlint
              pkgs.ghciwatch
              pkgs.postgresql_16
              pkgs.zlib
              pkgs.pkg-config
              pgStart
              pgStop
            ];
            shellHook = ''
              export DATABASE_URL="''${DATABASE_URL:-postgresql://treasury@localhost:5433/treasury}"
              export TEST_DATABASE_URL="''${TEST_DATABASE_URL:-postgresql://treasury@localhost:5433/treasury_test}"
              export PARTNER_BASE_URL="''${PARTNER_BASE_URL:-http://localhost:9400}"
            '';
          };
        });
    };
}
