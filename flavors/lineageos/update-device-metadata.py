#!/usr/bin/env nix-shell
#!nix-shell -i python -p python3 -I nixpkgs=../../pkgs
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

import json
import urllib.request

BRANCH = "lineage-18.1"
REF = "657efa4959113b10faa78b374c26140f8a180151"

def save(filename, data):
    open(filename, 'w').write(json.dumps(data, sort_keys=True, indent=2, separators=(',', ': ')))

def fetch_metadata():
    metadata = {}

    lineage_build_targets_str = urllib.request.urlopen(f"https://github.com/LineageOS/hudson/raw/{REF}/lineage-build-targets").read().decode()
    for line in lineage_build_targets_str.split("\n"):
        line = line.strip()
        if line == "":
            continue
        if line.startswith("#"):
            continue

        device, variant, branch, updatePeriod = line.split()
        if branch == BRANCH:
            metadata[device] = {
                'variant': variant,
                'branch': branch,
            }

    ###

    devices = json.load(urllib.request.urlopen(f"https://github.com/LineageOS/hudson/raw/{REF}/updater/devices.json"))
    for data in devices:
        if data['model'] not in metadata:
            continue

        vendor = data['oem']
        vendor = vendor.lower()

        # Workaround name inconsistency with LG
        if vendor == 'lg':
            vendor = 'lge'

        # Workaround google shamu source tree inconsistency
        if data['model'] == 'shamu':
            vendor = 'moto'

        # Workaround google flox source tree inconsistency
        if data['model'] == 'flox':
            vendor = 'asus'

        metadata[data['model']].update({
            'vendor': vendor,
            'name': data['name'],
            'lineage_recovery': data.get('lineage_recovery', False)
        })

    return metadata

if __name__ == '__main__':
    metadata = fetch_metadata()
    save('device-metadata.json', metadata)
