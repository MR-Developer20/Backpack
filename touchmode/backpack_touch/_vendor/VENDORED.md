# Vendored: python-elgato-streamdeck 0.9.8

`StreamDeck/` is <https://github.com/abcminiuser/python-elgato-streamdeck> 0.9.8 (the PyPI
`streamdeck` wheel), unmodified except that `ImageHelpers/` is left out: the launcher draws key
images with Qt (deckkeys.py), so Pillow is not needed. Licence: `StreamDeck/LICENSE`.

Vendored instead of Debian's `python3-elgato-streamdeck` because trixie ships 0.9.1, which predates
the Stream Deck + (dials, touch strip) and the Stream Deck Neo.
Runtime needs `libhidapi-libusb0` (the library opens `libhidapi-libusb.so.0` with ctypes).
To update: `pip download --no-deps streamdeck==X.Y.Z`, unzip, copy `StreamDeck/` here, drop
`ImageHelpers/`, copy the licence.
