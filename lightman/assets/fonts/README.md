# Embedded fonts

`lightman-regular.psf` and `lightman-bold.psf` are 8x16 Unicode-mapped PSF inputs
obtained from Debian/Ubuntu `console-setup-linux`'s `Lat15-Terminus16.psf.gz`
and `Lat15-TerminusBold16.psf.gz`. They derive from **Terminus Font**, copyright
(c) 2010 Dimitar Toshkov Zhekov. See [OFL.txt](OFL.txt) for the complete SIL Open
Font License 1.1 and reserved-name notice. Lightman's converted/embedded
derivatives are named Lightman Regular and Lightman Bold.

The build embeds ASCII 32–126, with blank control characters. Firmware supplies
DEC drawing glyphs separately. Font rows use the high bit as the left pixel.
These font assets remain under the OFL; the rest of Lightman's original source
uses the repository MIT license.

The fixed runtime set consists of Regular and Bold. Setup selects the base
font; SGR bold always chooses the Bold slot. Developers can replace either at
build time:

```sh
cmake -S lightman/firmware -B lightman/build/pico \
  -DPICO_SDK_PATH=/path/to/pico-sdk \
  -DLIGHTMAN_REGULAR_FONT=/absolute/path/regular.psf \
  -DLIGHTMAN_BOLD_FONT=/absolute/path/bold.psf
cmake --build lightman/build/pico -j
```

Inputs must be uncompressed PSF1 or PSF2, 8x16, with a Unicode mapping covering
printable ASCII. The converter rejects incompatible or truncated files. Font
changes automatically regenerate `fonts.h`; Python is a build dependency only.
Preserve the license/attribution of any replacement fonts. Font dimensions and
slot count are fixed in this baseline; adding different cell sizes requires
corresponding renderer, layout, configuration and tests changes.
