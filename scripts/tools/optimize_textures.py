#!/usr/bin/env python3
"""
PaperVTT texture optimization script.
- Downscales source PNGs: 2K -> 1K (albedo/normal/roughness), 2K/1K -> 512 (AO/displacement)
- Patches .import files: VRAM compression (BPTC), mipmaps, anisotropic, normal map hints
"""

import os
import re
import sys
from pathlib import Path
from PIL import Image

TEXTURE_ROOT = Path(__file__).resolve().parent.parent.parent / "assets" / "world" / "textures"

# Patterns that should be capped at 512 (subtle utility maps)
SMALL_KEYWORDS = ("displacement", "displace", "ambientocclusion", "ambient_occlusion", "_ao.", "_ao_", "height")
# Patterns that identify normal maps
NORMAL_KEYWORDS = ("normal", "_norm_", "_norm.", "normalgl", "normaldx", "normal_gl", "normal_dx")

STATS = {"resized": [], "skipped": 0, "import_patched": 0}


def get_target_size(name_lower: str, w: int, h: int) -> tuple[int, int]:
    if any(k in name_lower for k in SMALL_KEYWORDS):
        return (min(w, 512), min(h, 512))
    # Everything else caps at 1024
    return (min(w, 1024), min(h, 1024))


def is_normal_map(name_lower: str) -> bool:
    return any(k in name_lower for k in NORMAL_KEYWORDS)


def resize_image(png_path: Path) -> bool:
    name_lower = png_path.name.lower()
    try:
        with Image.open(png_path) as img:
            w, h = img.size
            tw, th = get_target_size(name_lower, w, h)
            if (w, h) == (tw, th):
                return False
            # Use LANCZOS for quality downsample
            resized = img.resize((tw, th), Image.LANCZOS)
            resized.save(png_path, optimize=False)  # keep import files simple
            STATS["resized"].append(f"{png_path.relative_to(TEXTURE_ROOT)}  {w}x{h} -> {tw}x{th}")
            return True
    except Exception as e:
        print(f"  WARN resize failed {png_path}: {e}", file=sys.stderr)
        return False


def patch_import_file(import_path: Path) -> bool:
    try:
        content = import_path.read_text()
        name_lower = import_path.stem.lower()  # stem = "foo.png", stem of stem = "foo"
        # Strip the .png from the .import name to get the original texture name
        tex_name_lower = Path(import_path.stem).stem.lower()
        normal = is_normal_map(tex_name_lower)

        def replace_param(text: str, key: str, value: str) -> str:
            pattern = rf"^({re.escape(key)}=).*$"
            replacement = rf"\g<1>{value}"
            new_text = re.sub(pattern, replacement, text, flags=re.MULTILINE)
            if new_text == text:
                # Key not present — append before the end of [params] section isn't trivial;
                # just append to end of file instead.
                new_text = text.rstrip() + f"\n{key}={value}\n"
            return new_text

        new_content = content
        new_content = replace_param(new_content, "compress/mode", "2")          # VRAM Compressed
        new_content = replace_param(new_content, "compress/high_quality", "true")  # BPTC/BC7 desktop
        new_content = replace_param(new_content, "mipmaps/generate", "true")
        if normal:
            new_content = replace_param(new_content, "compress/normal_map", "1")

        if new_content != content:
            import_path.write_text(new_content)
            STATS["import_patched"] += 1
            return True
        return False
    except Exception as e:
        print(f"  WARN patch failed {import_path}: {e}", file=sys.stderr)
        return False


def main():
    print(f"Scanning {TEXTURE_ROOT} ...")
    png_files = sorted(TEXTURE_ROOT.rglob("*.png"))
    print(f"Found {len(png_files)} PNG files\n")

    for png in png_files:
        resize_image(png)

    import_files = sorted(TEXTURE_ROOT.rglob("*.import"))
    print(f"Found {len(import_files)} .import files\n")
    for imp in import_files:
        patch_import_file(imp)

    print(f"\n=== Results ===")
    print(f"Images resized:   {len(STATS['resized'])}")
    print(f"Images unchanged: {len(png_files) - len(STATS['resized'])}")
    print(f"Imports patched:  {STATS['import_patched']}")
    if STATS["resized"]:
        print("\nResized files:")
        for entry in STATS["resized"]:
            print(f"  {entry}")


if __name__ == "__main__":
    main()
