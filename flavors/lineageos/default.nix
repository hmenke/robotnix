# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
with lib;
let
  deviceMetadata = importJSON ./device-metadata.json;
  _deviceDirs = importJSON ./device-dirs.json;
  vendorDirs = importJSON ./vendor-dirs.json;

  # TODO: Condition on soc name?
  dtbReproducibilityFix = ''
    sed -i \
      's/^DTB_OBJS := $(shell find \(.*\))$/DTB_OBJS := $(sort $(shell find \1))/' \
      arch/arm64/boot/Makefile
  '';
  kernelsNeedFix = [ # Only verified marlin reproducibility is fixed by this, however these other repos have the same issue
    "kernel/asus/sm8150"
    "kernel/bq/msm8953"
    "kernel/essential/msm8998"
    "kernel/google/marlin"
    "kernel/leeco/msm8996"
    "kernel/lge/msm8996"
    "kernel/motorola/msm8996"
    "kernel/motorola/msm8998"
    "kernel/motorola/sdm632"
    "kernel/nubia/msm8998"
    "kernel/oneplus/msm8996"
    "kernel/oneplus/sdm845"
    "kernel/oneplus/sm8150"
    "kernel/razer/msm8998"
    "kernel/samsung/sdm670"
    "kernel/sony/sdm660"
    "kernel/xiaomi/jason"
    "kernel/xiaomi/msm8998"
    "kernel/xiaomi/sdm660"
    "kernel/xiaomi/sdm845"
    "kernel/yandex/sdm660"
    "kernel/zuk/msm8996"
  ];
  deviceDirs = mapAttrs' (n: v: nameValuePair n (v // (optionalAttrs (elem n kernelsNeedFix) { postPatch = dtbReproducibilityFix; }))) _deviceDirs;

  supportedDevices = attrNames (filterAttrs (n: v: v.branch == LineageOSRelease) deviceMetadata);

  # TODO: Move this filtering into vanilla/graphene
  filterDirAttrs = dir: filterAttrs (n: v: elem n ["rev" "sha256" "url" "postPatch"]) dir;
  filterDirsAttrs = dirs: mapAttrs (n: v: filterDirAttrs v) dirs;

  LineageOSRelease = "lineage-18.1";
in mkIf (config.flavor == "lineageos")
{
  androidVersion = mkDefault 11;

  productNamePrefix = "lineage_"; # product names start with "lineage_"

  buildDateTime = mkDefault 1614623709;

  # LineageOS uses this by default. If your device supports it, I recommend using variant = "user"
  variant = mkDefault "userdebug";

  warnings = optional (
      (config.device != null) &&
      !(elem config.device supportedDevices) &&
      (config.deviceFamily != "generic")
    )
    "${config.device} is not a supported device for LineageOS";

  source.dirs = mkMerge ([
    (lib.importJSON (./. + "/repo-${LineageOSRelease}.json"))

    {
      "vendor/lineage".patches = [
        ./0001-Remove-LineageOS-keys.patch
        (pkgs.substituteAll {
          src = ./0002-bootanimation-Reproducibility-fix.patch;
          inherit (pkgs) imagemagick;
        })
        ./0003-kernel-Set-constant-kernel-timestamp.patch
      ];
      "system/extras".patches = [
        # pkgutil.get_data() not working, probably because we don't use their compiled python
        (pkgs.fetchpatch {
          url = "https://github.com/LineageOS/android_system_extras/commit/7da4b29321eb7ebce9eb9a43d0fbd85d0aa1e870.patch";
          sha256 = "0pv56lypdpsn66s7ffcps5ykyfx0hjkazml89flj7p1px12zjhy1";
          revert = true;
        })
      ];

      # LineageOS will sometimes force-push to this repo, and the older revisions are garbage collected.
      # So we'll just build chromium webview ourselves.
      "external/chromium-webview".enable = false;
    }
  ] ++ optionals (deviceMetadata ? "${config.device}") [
    # Device-specific source dirs
    (let
      vendor = toLower deviceMetadata.${config.device}.vendor;
      relpathWithDependencies = relpath: [ relpath ] ++ (flatten (map (p: relpathWithDependencies p) deviceDirs.${relpath}.deps));
      relpaths = relpathWithDependencies "device/${vendor}/${config.device}";
    in filterDirsAttrs (getAttrs relpaths deviceDirs))

    # Vendor-specific source dirs
    (let
      _vendor = toLower deviceMetadata.${config.device}.vendor;
      vendor = if config.device == "shamu" then "motorola" else _vendor;
      relpath = "vendor/${vendor}";
    in filterDirsAttrs (getAttrs [relpath] vendorDirs))
  ] ++ optional (config.device == "bacon")
    # Bacon needs vendor/oppo in addition to vendor/oneplus
    # See https://github.com/danielfullmer/robotnix/issues/26
    (filterDirsAttrs (getAttrs ["vendor/oppo"] vendorDirs))
  );

  source.manifest.url = mkDefault "https://github.com/LineageOS/android.git";
  source.manifest.rev = mkDefault "refs/heads/${LineageOSRelease}";

  # Enable robotnix-built chromium / webview
  apps.chromium.enable = mkDefault true;
  webview.chromium.availableByDefault = mkDefault true;
  webview.chromium.enable = mkDefault true;

  # This is the prebuilt webview apk from LineageOS. Adding this here is only
  # for convenience if the end-user wants to set `webview.prebuilt.enable = true;`.
  webview.prebuilt.apk = config.source.dirs."external/chromium-webview".src + "/prebuilt/${config.arch}/webview.apk";
  webview.prebuilt.availableByDefault = mkDefault true;
  removedProductPackages = [ "webview" ];

  envPackages = [ pkgs.openssl.dev ]; # Needed by included kernel build for some devices (pioneer at least)

  envVars.RELEASE_TYPE = mkDefault "EXPERIMENTAL";  # Other options are RELEASE NIGHTLY SNAPSHOT EXPERIMENTAL

  # LineageOS flattens all APEX packages: https://review.lineageos.org/c/LineageOS/android_vendor_lineage/+/270212
  # I can't find the CI config where this env var is set, but all device ROMS I
  # tried had flattened APEX packages as of 2020-07-22
  signing.apex.enable = false;
  envVars.OVERRIDE_TARGET_FLATTEN_APEX = "true";

  # LineageOS needs this additional command line argument to enable
  # backuptool.sh, which runs scripts under /system/addons.d
  otaArgs = [ "--backup=true" ];
}
