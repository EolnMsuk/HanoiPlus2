"""Read-only source/project/resource checks. Runs on Windows or macOS, no SDK.

Does not compile Objective-C, build an app, sign, or create IPA/TIPA packages.
The original references are optional in CI; prepared resources are mandatory.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import struct
import wave
import xml.etree.ElementTree as ET
import zipfile
import zlib
from prepare_assets import ROOT, ORIGINAL_DIR, RESOURCE_NAMES, IPA_SHA256, png_chunks, unfilter


def read_project(path):
    # OpenStep property-list reader for the checked-in project (no dependencies).
    source = path.read_text(encoding='utf-8').split('\n', 1)[1]
    tokens = re.findall(r'"(?:[^"\\]|\\.)*"|[{}()=;,]|[^\s{}()=;,]+', source)
    index = 0
    def take(expected=None):
        nonlocal index
        value = tokens[index]
        index += 1
        if expected is not None:
            assert value == expected, (expected, value)
        return value
    def value():
        token = take()
        if token == '{':
            result = {}
            while tokens[index] != '}':
                key = take()
                key = json.loads(key) if key.startswith('"') else key
                take('=')
                assert key not in result, f'Duplicate project key: {key}'
                result[key] = value()
                take(';')
            take('}')
            return result
        if token == '(':
            result = []
            while tokens[index] != ')':
                result.append(value())
                if tokens[index] == ',': take(',')
                else: assert tokens[index] == ')'
            take(')')
            return result
        return json.loads(token) if token.startswith('"') else token
    result = value()
    assert index == len(tokens), 'Trailing project tokens'
    return result


def check_png(path):
    chunks = png_chunks(path.read_bytes())
    assert not any(kind == b'CgBI' for kind, _ in chunks), path
    header = next(data for kind, data in chunks if kind == b'IHDR')
    w, h, depth, color, compression, filtering, interlace = struct.unpack('>IIBBBBB', header)
    assert compression == filtering == interlace == 0, path
    channels = {2: 3, 3: 1, 6: 4}[color]
    stride = (w * depth * channels + 7) // 8
    raw = zlib.decompress(b''.join(data for kind, data in chunks if kind == b'IDAT'))
    assert len(raw) == h * (stride + 1), path
    assert all(raw[y * (stride + 1)] in range(5) for y in range(h)), path
    return w, h, depth, color, raw


def check_resources(inspect_reference=True):
    manifest = json.loads((ROOT / 'ios/resource-manifest.json').read_text())
    assert manifest['reference_ipa_sha256'] == IPA_SHA256
    entries = manifest['resources']
    assert [entry['name'] for entry in entries] == RESOURCE_NAMES
    directory = ROOT / 'ios/HanoiPlus/Resources'
    assert {p.name for p in directory.iterdir()} == set(RESOURCE_NAMES)
    assert len(RESOURCE_NAMES) == 17
    assert [sum(name.endswith(suffix) for name in RESOURCE_NAMES) for suffix in ('.png', '.wav', '.jpg')] == [13, 2, 2]
    for entry in entries:
        path = directory / entry['name']
        assert hashlib.sha256(path.read_bytes()).hexdigest() == entry['prepared_sha256'], path
        if path.suffix == '.png':
            w, h, _, _, _ = check_png(path)
            assert [w, h] == entry['source_dimensions'], path
    assert sum(entry['normalized_cgbi'] for entry in entries) == 11
    for name in ('click.wav', 'gong.wav'):
        with wave.open(str(directory / name), 'rb') as sound:
            assert sound.getnframes() > 0 and sound.getsampwidth() > 0
    catalog = ROOT / 'ios/HanoiPlus/Assets.xcassets/AppIcon.appiconset'
    icons = json.loads((catalog / 'Contents.json').read_text())['images']
    assert len(icons) == 9
    for entry in icons:
        pixels = int(float(entry['size'].split('x')[0]) * int(entry['scale'][0]))
        w, h, depth, color, _ = check_png(catalog / entry['filename'])
        assert (w, h, depth, color) == (pixels, pixels, 8, 2), entry # Opaque RGB.
    print('Assets: 17 resources (13 PNGs, 2 WAVs, 2 JPEGs), hashes, PNG CRC/scanlines, WAVs and 9 opaque icon slots passed.')
    ipa = ORIGINAL_DIR / 'Hanoi Plus 1.1.ipa'
    if inspect_reference and ipa.exists():
        assert hashlib.sha256(ipa.read_bytes()).hexdigest() == IPA_SHA256
        with zipfile.ZipFile(ipa) as archive:
            for entry in entries:
                source = archive.read(entry['archive_path'])
                assert hashlib.sha256(source).hexdigest() == entry['source_sha256']
                assert (ORIGINAL_DIR / entry['archive_path']).read_bytes() == source
                if not entry['normalized_cgbi']: continue
                original = png_chunks(source)
                w, h = entry['source_dimensions']
                bgra = unfilter(zlib.decompress(b''.join(d for k, d in original if k == b'IDAT'), -15), w, h)
                _, _, _, _, raw = check_png(directory / entry['name'])
                rgba = unfilter(raw, w, h)
                for source_row, prepared_row in zip(bgra, rgba):
                    for i in range(0, len(source_row), 4):
                        b, g, r, a = source_row[i:i + 4]
                        rr, gg, bb, aa = prepared_row[i:i + 4]
                        assert a == aa
                        if a:
                            assert all(abs(c - (cc * a + 127) // 255) <= 1 for c, cc in zip((r, g, b), (rr, gg, bb)))
                        else:
                            assert (rr, gg, bb) == (0, 0, 0)
            assert archive.read('iTunesArtwork') == (ORIGINAL_DIR / 'iTunesArtwork').read_bytes()
            for path in (ORIGINAL_DIR / 'Payload/Hanoi Plus.app').rglob('*'):
                if path.is_file(): assert path.read_bytes() == archive.read(path.relative_to(ORIGINAL_DIR).as_posix()), path
            binary = archive.read('Payload/Hanoi Plus.app/Hanoi Plus')
            assert hashlib.sha256(binary).hexdigest() == '9683769faca37bc918f43a384b06a5983f006e6fc88489506fd5d5146915b310'
        print('References: unchanged IPA, entire extracted app and artwork; CgBI channel/alpha round-trip passed.')


def check_project():
    path = ROOT / 'ios/HanoiPlus.xcodeproj/project.pbxproj'
    project = read_project(path)
    objects = project['objects']
    root = objects[project['rootObject']]
    assert root['isa'] == 'PBXProject' and len(root['targets']) == 1
    target_id = root['targets'][0]
    target = objects[target_id]
    assert target['name'] == target['productName'] == 'HanoiPlus'
    assert objects[target['productReference']]['path'] == 'HanoiPlus.app'
    def walk(value):
        if isinstance(value, dict):
            for child in value.values(): walk(child)
        elif isinstance(value, list):
            for child in value: walk(child)
        elif isinstance(value, str) and re.fullmatch('[0-9A-F]{24}', value):
            assert value in objects, value
    walk(objects)
    files = {}
    def group(group_id, base):
        item = objects[group_id]
        base = base / item.get('path', '')
        for child_id in item['children']:
            child = objects[child_id]
            if child['isa'] == 'PBXGroup': group(child_id, base)
            elif child['sourceTree'] == '<group>':
                filename = base / child['path']
                assert filename.exists(), filename
                files[child_id] = filename
    group(root['mainGroup'], ROOT / 'ios')
    phases = {objects[key]['isa']: objects[key] for key in target['buildPhases']}
    def phase_files(phase): return [files[objects[key]['fileRef']] for key in phases[phase]['files']]
    resources = phase_files('PBXResourcesBuildPhase')
    assert len(resources) == 18 and {p.name for p in resources} == set(RESOURCE_NAMES + ['Assets.xcassets'])
    sources = phase_files('PBXSourcesBuildPhase')
    assert len(sources) == 10
    assert set(sources) == {p for p in (ROOT / 'ios/HanoiPlus').iterdir() if p.suffix in ('.m', '.c')}
    for configuration in objects[target['buildConfigurationList']]['buildConfigurations']:
        settings = objects[configuration]['buildSettings']
        assert settings['PRODUCT_BUNDLE_IDENTIFIER'] == 'com.hanoiplus.v2'
        assert settings['TARGETED_DEVICE_FAMILY'] == '1'
        assert settings['COMPRESS_PNG_FILES'] == 'NO'
        assert settings['INFOPLIST_FILE'] == 'HanoiPlus/Info.plist'
    for configuration in objects[root['buildConfigurationList']]['buildConfigurations']:
        settings = objects[configuration]['buildSettings']
        assert settings['IPHONEOS_DEPLOYMENT_TARGET'] == '16.0'
        assert settings['SDKROOT'] == 'iphoneos' and settings['ARCHS'] == 'arm64'
        assert settings['CLANG_ENABLE_OBJC_ARC'] == 'YES'
    scheme = ET.parse(path.parent / 'xcshareddata/xcschemes/HanoiPlus.xcscheme')
    for reference in scheme.findall('.//BuildableReference'):
        assert reference.get('BlueprintIdentifier') == target_id
        assert reference.get('BuildableName') == 'HanoiPlus.app'
        assert reference.get('ReferencedContainer') == 'container:HanoiPlus.xcodeproj'
    info = plistlib.loads((ROOT / 'ios/HanoiPlus/Info.plist').read_bytes())
    assert info['CFBundleDisplayName'] == 'Hanoi Plus'
    assert set(info['UISupportedInterfaceOrientations']) == {'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'}
    assert info['UIRequiredDeviceCapabilities'] == ['arm64'] and 'UILaunchScreen' in info
    config = info['UIApplicationSceneManifest']['UISceneConfigurations']['UIWindowSceneSessionRoleApplication'][0]
    assert config['UISceneDelegateClassName'] == 'SceneDelegate'
    assert not {'SignerIdentity', 'CFBundleResourceSpecification'} & info.keys()
    print('Project: OpenStep references/phases, shared scheme, ARC/ARM64/iOS 16 contract and startup plist passed.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-reference', action='store_true', help='CI: validate committed source/assets without inspecting optional references')
    args = parser.parse_args()
    check_resources(inspect_reference=not args.skip_reference)
    check_project()
