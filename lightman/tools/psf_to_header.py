#!/usr/bin/env python3
## @file psf_to_header.py
# @brief Validate two Unicode-mapped 8x16 PSF fonts and generate a C++ glyph table.
"""Convert two Unicode-mapped 8x16 PSF1/PSF2 fonts into embedded ASCII tables."""
import argparse
from pathlib import Path
import struct


## @brief Decode printable ASCII glyphs from an uncompressed PSF1 or PSF2 font.
# @param path Path to an 8x16 font with a complete printable-ASCII Unicode mapping.
# @return A list of 128 sixteen-byte glyphs; control-code glyphs are blank.
# @exception ValueError Unsupported dimensions, encoding, mapping or record contents.
# @exception OSError The input file cannot be read.
# @exception struct.error A binary header is too short to unpack.
def read_font(path):
    data = Path(path).read_bytes()
    if data[:2] == b'\x36\x04':
        mode, height = data[2:4]
        count, size, start, width = (512 if mode & 1 else 256), height, 4, 8
        unicode_table = bool(mode & 2)
        wide = True
    elif data[:4] == b'\x72\xb5\x4a\x86':
        _, version, start, flags, count, size, height, width = struct.unpack_from('<8I', data)
        if version != 0:
            raise ValueError('Unsupported PSF2 version')
        unicode_table, wide = bool(flags & 1), False
    else:
        raise ValueError(f'{path}: not a PSF font')
    if (width, height, size) != (8, 16, 16):
        raise ValueError(f'{path}: font must be 8x16')
    end = start + count * size
    if len(data) < end or not unicode_table:
        raise ValueError(f'{path}: truncated font or missing Unicode mapping')
    mapping = {}
    table = data[end:]
    if wide:
        if len(table) % 2:
            raise ValueError('Truncated PSF1 Unicode table')
        entries, entry = [], []
        for cp in struct.unpack('<' + 'H' * (len(table)//2), table):
            if cp == 0xffff:
                entries.append(entry)
                entry = []
            else:
                entry.append(cp)
        for i, entry in enumerate(entries):
            for cp in entry:
                if cp == 0xfffe:
                    break  # Multi-codepoint sequences are not single glyph aliases.
                mapping.setdefault(cp, i)
    else:
        entries = table.split(b'\xff')[:-1]
        for i, entry in enumerate(entries):
            for ch in entry.split(b'\xfe')[0].decode('utf-8'):
                mapping.setdefault(ord(ch), i)
    if len(entries) != count:
        raise ValueError('Wrong number of Unicode entries')
    output = []
    for cp in range(128):
        if cp < 32 or cp == 127:
            output.append(bytes(16))
        else:
            if cp not in mapping:
                raise ValueError(f'{path}: missing ASCII character {cp}')
            i = mapping[cp]
            output.append(data[start+i*size:start+(i+1)*size])
    return output


## @brief Parse font/output paths and write the generated two-font C++ header.
# @details Input validation and file errors propagate to the command-line caller.
# @return None on successful generation.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('regular')
    parser.add_argument('bold')
    parser.add_argument('output')
    args = parser.parse_args()
    fonts = [read_font(args.regular), read_font(args.bold)]
    text = '/** @file fonts.h\n * @brief Generated ASCII glyph rows; bit 7 is the leftmost pixel.\n */\n'
    text += '#pragma once\n#include <cstdint>\n'
    text += '/** @brief Glyphs indexed by font slot, ASCII code and row. */\n'
    text += 'inline constexpr uint8_t font_data[2][128][16] = {\n'
    for font in fonts:
        text += '{\n' + ''.join('{' + ','.join(f'0x{x:02x}' for x in glyph) + '},\n' for glyph in font) + '},\n'
    Path(args.output).write_text(text + '};\n')


if __name__ == '__main__':
    main()
