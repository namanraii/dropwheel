# Dropwheel

A personal menu bar app I use on my Mac when I need a file in another format. Conversion stays on this machine. Nothing is uploaded.

## How I use it

1. Drag a file in Finder.
2. Tap Shift. A wheel opens around the pointer.
3. Move onto a format and release the mouse. Dropwheel writes a new file next to the original and does not overwrite it.
4. After the wheel is open, Command shows tools and Control shows actions such as AirDrop, Copy, Move, and Terminal.

Command or Option by themselves do not open the wheel, so a normal Finder drag still behaves like a Finder drag.

The app lives in the menu bar, not the Dock. Settings covers image quality, audio bitrate, PDF page sharpness, and launch at login.

## What it handles

- Images: JPG, PNG, WebP, HEIC, TIFF, AVIF, BMP, GIF, and PDF.
- Audio: MP3, M4A, WAV, FLAC, Ogg, Opus, AIFF, and WMA.
- Video: MP4, MOV, MKV, WebM, AVI, WMV, GIF, and MP3.
- PDF, Word, text, Markdown, EPUB, subtitles, spreadsheets, and zip, tar, and gzip archives.

The wheel only shows formats that fit the file you dragged. PowerPoint, Excel, and higher-fidelity Office export use LibreOffice when it is installed:

```sh
brew install --cask libreoffice
```

RAR extract needs `unar` (`brew install unar`). Images, audio, and video use ImageMagick, ffmpeg, and Ghostscript when they are on the Mac.

## Build

```sh
make run
```

That builds `dist/Dropwheel.app`. If macOS blocks the first open, right-click the app and choose Open. Moving it to `/Applications` makes launch-at-login reliable.
