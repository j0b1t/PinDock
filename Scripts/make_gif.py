#!/usr/bin/env python3
"""Assemble a palette-quantized, scaled GIF from PNG frames."""
import glob
import os
import sys

from PIL import Image

def main() -> None:
    if len(sys.argv) < 3:
        print("usage: make_gif.py <framedir> <out.gif> [max_width] [duration_ms]", file=sys.stderr)
        sys.exit(2)
    framedir, dest = sys.argv[1], sys.argv[2]
    max_width = int(sys.argv[3]) if len(sys.argv) > 3 else 480
    duration = int(sys.argv[4]) if len(sys.argv) > 4 else 90

    paths = sorted(glob.glob(os.path.join(framedir, "frame-*.png")))
    if not paths:
        print(f"no frames in {framedir}", file=sys.stderr)
        sys.exit(1)

    images = []
    for path in paths:
        im = Image.open(path).convert("RGBA")
        # Composite onto dark gray so glass/alpha looks like the HUD shots.
        bg = Image.new("RGB", im.size, (18, 18, 20))
        bg.paste(im, mask=im.split()[-1])
        if bg.width > max_width:
            h = int(bg.height * (max_width / bg.width))
            bg = bg.resize((max_width, h), Image.Resampling.LANCZOS)
        images.append(bg)

    # Shared palette so tab switches don't flicker colors.
    sample = images[min(len(images) // 3, len(images) - 1)]
    pal = sample.quantize(colors=64, method=Image.Quantize.MEDIANCUT)
    quantized = [im.quantize(palette=pal, dither=Image.Dither.NONE) for im in images]

    quantized[0].save(
        dest,
        save_all=True,
        append_images=quantized[1:],
        duration=duration,
        loop=0,
        optimize=True,
        disposal=2,
    )
    kb = os.path.getsize(dest) / 1024
    print(f"wrote {dest} ({kb:.0f}K, {len(quantized)} frames)")


if __name__ == "__main__":
    main()
