# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

# https://www.reddit.com/r/GrapheneOS/comments/bpcttk/avb_key_auditor_app/
{ callPackage, lib, substituteAll, fetchFromGitHub, androidPkgs, jdk, gradle,
  domain ? "example.org",
  applicationName ? "Robotnix Auditor",
  applicationId ? "org.robotnix.auditor",
  signatureFingerprint ? "", # Signature that this app will be signed by.
  device ? "",
  avbFingerprint ? ""
}:
let
  androidsdk = androidPkgs.sdk (p: with p; [ cmdline-tools-latest platforms-android-30 build-tools-30-0-2 ]);
  buildGradle = callPackage ./gradle-env.nix {};
  supportedDevices = import ./supported-devices.nix;
in
buildGradle rec {
  name = "Auditor-${version}.apk";
  version = "25"; # Latest as of 2021-02-14

  envSpec = ./gradle-env.json;

  src = fetchFromGitHub {
    owner = "grapheneos";
    repo = "Auditor";
    rev = version;
    sha256 = "0nqj31j34hsqml2h0sik4ra7jv59qhmxw6jmwhdflii10j16pm6g";
  };

  patches = [
    # TODO: Enable support for passing multiple device fingerprints
    (substituteAll ({
      src = ./customized-auditor.patch;
      inherit domain applicationName applicationId ;
      signatureFingerprint = lib.toUpper signatureFingerprint;
    }
    // lib.genAttrs supportedDevices (d: if (device == d) then avbFingerprint else "DISABLED_CUSTOM_${d}")))
  ];

  # gradle2nix not working with the more recent version of com.android.tools.build:gradle for an unknown reason
  #
  # Caused by: org.gradle.internal.component.AmbiguousVariantSelectionException: The consumer was configured to find an API of a component, as well as attribute 'com.android.build.api.attributes.BuildTypeAttr' with value 'debug'. However we cannot choose between the following variants of project :app:
  #   - Configuration ':app:debugApiElements' variant android-base-module-metadata declares an API of a component, as well as attribute 'com.android.build.api.attributes.BuildTypeAttr' with value 'debug':
  #       - Unmatched attributes:
  #           - Provides attribute 'artifactType' with value 'android-base-module-metadata' but the consumer didn't ask for it
  #           - Provides attribute 'com.android.build.api.attributes.VariantAttr' with value 'debug' but the consumer didn't ask for it
  postPatch = ''
    substituteInPlace build.gradle --replace "com.android.tools.build:gradle:4.1.2" "com.android.tools.build:gradle:4.0.1"
  '';

  gradleFlags = [ "assembleRelease" ];

  ANDROID_HOME = "${androidsdk}/share/android-sdk";
  nativeBuildInputs = [ jdk ];

  installPhase = ''
    cp app/build/outputs/apk/release/app-release-unsigned.apk $out
  '';
}
