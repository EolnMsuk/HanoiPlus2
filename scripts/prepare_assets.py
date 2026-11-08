"""Prepare the supplied IPA assets locally with the Python standard library.

Run on Windows: python scripts/prepare_assets.py
Original inputs are read-only. Only the explicit 17 resources are extracted.
Icon resizing uses Windows System.Drawing via prepare_icons.ps1.
"""
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import zlib
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ORIGINAL_DIR = ROOT / 'Original'
RESOURCE_NAMES = (['base.png', 'new_game.png', 'continue.png', 'click.wav',
                   'gong.wav', 'hanoi.jpg', 'winScreen.jpg']
                  + [f'disk_{i}.png' for i in range(10)])
PNG_MAGIC = b'\x89PNG\r\n\x1a\n'
IPA_SHA256 = 'c1ac02370feac2a4fbc34d68b5dd4cdb4c656e3b6f7c24894a536ed93a84a1ad'


def png_chunks(data):
    if not data.startswith(PNG_MAGIC):
        raise ValueError('Not a PNG')
    offset, chunks = 8, []
    while offset < len(data):
        size = struct.unpack_from('>I', data, offset)[0]
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + size]
        if offset + 12 + size > len(data):
            raise ValueError('Truncated PNG')
        crc = struct.unpack_from('>I', data, offset + 8 + size)[0]
        if zlib.crc32(kind + payload) & 0xFFFFFFFF != crc:
            raise ValueError(f'Invalid {kind!r} CRC')
        chunks.append((kind, payload))
        offset += size + 12
        if kind == b'IEND':
            if offset != len(data):
                raise ValueError('Trailing PNG bytes')
            break
    if not chunks or chunks[-1] != (b'IEND', b''):
        raise ValueError('Missing IEND')
    return chunks


def chunk(kind, data):
    return (struct.pack('>I', len(data)) + kind + data
            + struct.pack('>I', zlib.crc32(kind + data) & 0xFFFFFFFF))


def paeth(a, b, c):
    p = a + b - c
    distances = (abs(p - a), abs(p - b), abs(p - c))
    return (a, b, c)[distances.index(min(distances))]


def unfilter(raw, width, height, bpp=4):
    stride = width * bpp
    if len(raw) != height * (stride + 1):
        raise ValueError('Unexpected scanline length')
    rows, previous = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        filtering = raw[start]
        row = bytearray(raw[start + 1:start + 1 + stride])
        if filtering not in range(5):
            raise ValueError('Unsupported PNG filter')
        for x in range(stride):
            left = row[x - bpp] if x >= bpp else 0
            above = previous[x]
            upper_left = previous[x - bpp] if x >= bpp else 0
            predictor = (0, left, above, (left + above) // 2,
                         paeth(left, above, upper_left))[filtering]
            row[x] = (row[x] + predictor) & 255
        rows.append(row)
        previous = row
    return rows


def normalize_png(data):
    chunks = png_chunks(data)
    header = next(value for kind, value in chunks if kind == b'IHDR')
    width, height, depth, color, compression, filtering, interlace = struct.unpack('>IIBBBBB', header)
    optimized = any(kind == b'CgBI' for kind, _ in chunks)
    if not optimized:
        # Preserve indexed PNGs; never run them through the RGBA path.
        return data, (width, height), False
    if (depth, color, compression, filtering, interlace) != (8, 6, 0, 0, 0):
        raise ValueError('Unsupported CgBI header')
    compressed = b''.join(value for kind, value in chunks if kind == b'IDAT')
    rows = unfilter(zlib.decompress(compressed, -15), width, height)
    straight = bytearray()
    for row in rows:
        straight.append(0)
        for i in range(0, len(row), 4):
            blue, green, red, alpha = row[i:i + 4]
            channels = [min(255, (c * 255 + alpha // 2) // alpha)
                        if alpha else 0 for c in (red, green, blue)]
            straight.extend((*channels, alpha))
    output = (PNG_MAGIC + chunk(b'IHDR', header)
              + chunk(b'IDAT', zlib.compress(bytes(straight), 9)) + chunk(b'IEND', b''))
    png_chunks(output)
    return output, (width, height), True


def prepare():
    ipa = ORIGINAL_DIR / 'Hanoi Plus 1.1.ipa'
    if hashlib.sha256(ipa.read_bytes()).hexdigest() != IPA_SHA256:
        raise ValueError('Reference IPA hash differs from the inspected input')
    output = ROOT / 'ios/HanoiPlus/Resources'
    output.mkdir(parents=True, exist_ok=True)
    entries = []
    with zipfile.ZipFile(ipa) as archive:
        for name in RESOURCE_NAMES:
            path = f'Payload/Hanoi Plus.app/{name}'
            source = archive.read(path)
            prepared, dimensions, normalized = source, None, False
            if name.endswith('.png'):
                prepared, dimensions, normalized = normalize_png(source)
            (output / name).write_bytes(prepared)
            entries.append({'name': name, 'archive_path': path,
                            'source_sha256': hashlib.sha256(source).hexdigest(),
                            'prepared_sha256': hashlib.sha256(prepared).hexdigest(),
                            'source_dimensions': dimensions, 'normalized_cgbi': normalized})
        if archive.read('iTunesArtwork') != (ORIGINAL_DIR / 'iTunesArtwork').read_bytes():
            raise ValueError('Original/iTunesArtwork differs from archive')
    subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy',
                    'Bypass', '-File', str(ROOT / 'scripts/prepare_icons.ps1')], check=True, cwd=ROOT)
    write_catalog()
    manifest = {'reference_ipa_sha256': IPA_SHA256,
                'orientation': 'unchanged; AssetLoader rotates artwork left once', 'resources': entries}
    (ROOT / 'ios/resource-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(f'Prepared {len(entries)} resources, including {sum(e["normalized_cgbi"] for e in entries)} CgBI PNGs, and icons.')


def write_catalog():
    catalog = ROOT / 'ios/HanoiPlus/Assets.xcassets'
    (catalog / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n', encoding='utf-8')
    sizes = [('20x20', '2x', 40), ('20x20', '3x', 60), ('29x29', '2x', 58),
             ('29x29', '3x', 87), ('40x40', '2x', 80), ('40x40', '3x', 120),
             ('60x60', '2x', 120), ('60x60', '3x', 180), ('1024x1024', '1x', 1024)]
    icons = [{'idiom': 'ios-marketing' if pixels == 1024 else 'iphone', 'size': size,
              'scale': scale, 'filename': f'Icon-{pixels}.png'} for size, scale, pixels in sizes]
    (catalog / 'AppIcon.appiconset/Contents.json').write_text(json.dumps({'images': icons, 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    prepare()
