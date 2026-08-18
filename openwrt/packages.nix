{
  pkgs,
  lib,
  config,
  ...
}: let
  depsIpk = config.build.depsIpkPackage;
  depsApk = config.build.depsApkPackage;
in {
  options.packages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = ''
      Extra packages to install. These are merely names of packages available
      to opkg/apk through the package source lists configured on the device, it is
      not currently possible to provide packages for installation without
      configuring an opkg source first.
    '';
  };

  config = {
    deploySteps.packages = {
      priority = 80;
      copy = lib.mkMerge [
        (lib.mkIf (config.deploy.packageManager == "opkg")
          ''
            scp ${depsIpk} device:/tmp/deps-${depsIpk.version}.ipk
          '')
        (lib.mkIf (config.deploy.packageManager == "apk")
          ''
            scp ${depsApk}/*.apk device:/tmp/deps-${depsApk.hash}.apk
          '')
      ];
      apply = lib.mkMerge [
        (lib.mkIf (config.deploy.packageManager == "opkg")
          ''
            if [ ${depsIpk.version} != "$(opkg info ${depsIpk.package_name} | grep Version | cut -d' ' -f2)" ]; then
              opkg update
              opkg install --autoremove --force-downgrade /tmp/deps-${depsIpk.version}.ipk
            fi
          '')

        (lib.mkIf (config.deploy.packageManager == "apk")
          ''
            if [ ${depsApk.hash} != "$(apk query --no-cache ${depsApk.package_name} | grep Version | cut -d' ' -f2)" ]; then
              apk update --no-cache
              apk add --no-cache --allow-untrusted /tmp/deps-${depsApk.hash}.apk
            fi
          '')
      ];
    };

    build.depsIpkPackage =
      pkgs.runCommand "deps.ipk"
      rec {
        package_name = ".extra-system-deps.";
        version = builtins.hashString "sha256" (toString config.packages);
        control = ''
          Package: ${package_name}
          Version: ${version}
          Architecture: all
          Description: extra system dependencies
          ${lib.optionalString (
            config.packages != []
          ) "Depends: ${lib.concatStringsSep ", " config.packages}"}
        '';
        passAsFile = ["control"];
      }
      ''
        mkdir -p deps/control deps/data
        cp $controlPath deps/control/control
        echo 2.0 > deps/debian-binary

        alias tar='command tar --numeric-owner --group=0 --owner=0'
        (cd deps/control && tar -czf ../control.tar.gz ./*)
        (cd deps/data && tar -czf ../data.tar.gz .)
        (cd deps && tar -zcf $out ./debian-binary ./data.tar.gz ./control.tar.gz)
      '';

    ## Ongoing issue.
    ## On your router `/etc/apk/arch` must contain
    ## - your router architecture
    ## - and "all".
    ## Set it manually before running dewclaw.
    ## https://github.com/openwrt/openwrt/issues/16953

    build.depsApkPackage = let
      # APKBUILD
      hash = builtins.hashString "sha256" (toString config.packages);
      package_name = "extra-system-deps";
      pkgname = package_name;
      pkgver = "1.0.0-r0";
      license = "GPLv2";
      url = "https://github.com/MakiseKurisu/dewclaw";
      arch = "all";
      pkgdesc = "extra system dependencies";
      depends =
        lib.optionalString (
          config.packages != []
        )
        lib.concatStringsSep " "
        config.packages;
    in
      pkgs.runCommand "deps.apk"
      {
        inherit hash;
        inherit package_name;
        name = "buildExtraDepsPkg";
        src = ./.;
        nativeBuildInputs = with pkgs; [
          apk-tools
        ];
      }
      ''
        export HOME=$(pwd)

        mkdir ./deps
        mkdir $out
        touch "$out/${hash}-deps.apk"

        apk mkpkg \
          --info "name:${pkgname}" \
          --info "version:${pkgver}" \
          --info "hashes:${hash}" \
          --info "description:${pkgdesc}" \
          --info "arch:${arch}" \
          --info "license:${license}" \
          --info "url:${url}" \
          --info "replaces:${package_name}" \
          --info "depends:${depends}" \
          --files "./deps" \
          --output "$out/${hash}-deps.apk"
      '';
  };
}
