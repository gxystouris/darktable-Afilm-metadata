# darktable-afilm-metadata

A darktable Lua script that takes the per-roll log from the [Afilm](https://afilm.app) app and writes each frame's camera settings into your scanned film photos.

Lab scans usually come back with no metadata at all. If you log your shots in Afilm, this script puts that information back where it belongs: camera, lens, aperture, shutter speed, ISO, date, location and your notes. It runs from a panel inside darktable's lighttable.

> **Note:** This is an independent project. It is not affiliated with or endorsed by darktable or Afilm.

---

## ⚠️ Before you use it

This script **writes metadata directly into your image files** (via ExifTool, overwriting the originals).
darktable itself never modifies image files; this script deliberately does. **Keep a backup of your scans.**

---

## What gets written

| Afilm field            | Written to                                    | Notes                                                        |
|------------------------|-----------------------------------------------|--------------------------------------------------------------|
| Camera name            | `Model`                                       |                                                              |
| ISO                    | `ISO`                                         |                                                              |
| Lens name              | `LensModel`                                   |                                                              |
| Lens name              | `FocalLength`                                 | Only if the lens name contains exactly one value, e.g. `35mm` |
| Aperture               | `FNumber`                                     | Approximate values like `~f/8` are written as `8`             |
| Shutter speed          | `ExposureTime`                                | `~2` becomes `2`; ranges like `2-3` are averaged to `2.5`     |
| Date                   | `DateTimeOriginal`                            |                                                              |
| Note                   | `XMP-dc:Description`, `IPTC:Caption-Abstract` |                                                              |
| Location               | `GPSLatitude`, `GPSLongitude` (+ N/S, E/W)    |                                                              |

---

## Requirements

- **darktable** with Lua support (included in the standard builds)
- **ExifTool**, available on your system `PATH` → [exiftool.org](https://exiftool.org)

  To check, open a terminal and run:
  ```
  exiftool -ver
  ```
  If you see a version number, you're set.

  **Windows tip:** the download contains `exiftool(-k).exe`. Rename it to `exiftool.exe`, then add the folder that contains it to your `Path` environment variable.

---

## Installation

1. Download `import_Afilm_metadata.lua` from this repository.
2. Copy it into darktable's Lua scripts folder:

   | OS                  | Folder                                                  |
   |---------------------|---------------------------------------------------------|
   | Windows             | `%LOCALAPPDATA%\darktable\lua\contrib\`                 |
   | Linux *(untested)*  | `~/.config/darktable/lua/contrib/`                      |
   | macOS *(untested)*  | `~/Library/Application Support/darktable/lua/contrib/` |

   Create the folders if they don't exist.
3. Restart darktable, go to **preferences → lua options** and enable **import_Afilm_metadata**.
4. Restart darktable again. A new **import Afilm metadata** section appears in the lighttable's left panel.

---

## Usage

**Before you start**

- Put the Afilm `.json` export in the **same folder** as the scans, and make sure it is the **only** `.json` file there.
- Name your scans so they **sort in shooting/scanning order** (e.g. `r001`, `r002`, `r003` …). Frame 1 goes to the first file, frame 2 to the second, and so on.

**Steps**

1. Import the roll into darktable, then double-click its folder in the **collections** module so only that roll is shown.
2. In the lighttable's left panel, open **import Afilm metadata** and click **Detect JSON from current folder**.
   (You can also pick the file yourself with the file button.)
3. Click **Apply metadata to collection**.
4. Wait for the **Done** message. The images are removed from and re-imported into darktable so it picks up the new metadata. The files on disk stay where they are.

**Tips**

- **Run this right after importing, before you start editing.** Edits stored only in darktable's library can be lost when the images are re-imported. They are restored from `.xmp` sidecars if sidecar writing is on, which is the default.
- If the number of images doesn't match the number of frames in the `.json`, **nothing is written**, and the message shows both counts. Add or remove images until they match, then try again.
- Something went wrong? Check **Help → Show Log** for the details.

---

## Known limitations

- **Tested on Windows only.** Linux and macOS should work but haven't been tested. Reports are welcome!
- **macOS:** if darktable is started from the Dock, it may not find an ExifTool installed through Homebrew, because apps don't always see the terminal's `PATH`.
- **Frames are matched by filename order only.** Partial rolls or skipped frames aren't supported yet; a manual mapping option is planned.
- **Some special characters in notes may appear as `?`** if the `.json` stores them as escape codes (`\u00f6`).

Found a bug or have an idea? [Open an issue](../../issues).

---

## Support

If you liked this script, you can support me by buying me a coffee ☕
👉 [buymeacoffee.com/gx.photography](https://buymeacoffee.com/gx.photography)

---

## License

Copyright © 2026 George Xystouris

This project is licensed under the **GNU General Public License v2.0 or later**. See [LICENSE](LICENSE) for the full text.
You are free to use, modify and share it; modified versions must stay under the same license and keep the original copyright notice.
