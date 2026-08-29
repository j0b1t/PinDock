#!/usr/bin/env python3
"""Assemble a palette-quantized, scaled GIF from PNG frames."""
import glob
import os
import sys

from PIL import Image

def main() -> None:
    if len(sys.argv) < 3:
        print("usage: make_gif.py <framedir> <out.gif> [max_width] [duration_ms] [colors]", file=sys.stderr)
        sys.exit(2)
    framedir, dest = sys.argv[1], sys.argv[2]
    max_width = int(sys.argv[3]) if len(sys.argv) > 3 else 1440
    duration = int(sys.argv[4]) if len(sys.argv) > 4 else 90
    colors = int(sys.argv[5]) if len(sys.argv) > 5 else 256

    paths = sorted(glob.glob(os.path.join(framedir, "frame-*.png")))
    if not paths:
        print(f"no frames in {framedir}", file=sys.stderr)
        sys.exit(1)

    images = []
    for path in paths:
        im = Image.open(path).convert("RGBA")
        # Match still screenshots: opaque black behind window chrome / shadow.
        bg = Image.new("RGB", im.size, (0, 0, 0))
        bg.paste(im, mask=im.split()[-1])
        if bg.width > max_width:
            h = max(1, int(round(bg.height * (max_width / bg.width))))
            bg = bg.resize((max_width, h), Image.Resampling.LANCZOS)
        images.append(bg)

    w0, h0 = images[0].size
    images = [
        im.resize((w0, h0), Image.Resampling.LANCZOS) if im.size != (w0, h0) else im
        for im in images
    ]

    # Shared palette built from several frames so blue switches stay blue.
    idxs = [0, len(images) // 2, len(images) - 1]
    picks = [images[i] for i in idxs]
    w = min(im.width for im in picks)
    h = min(im.height for im in picks)
    picks = [im.crop((0, 0, w, h)) for im in picks]
    sample = Image.new("RGB", (w, h * len(picks)))
    for i, im in enumerate(picks):
        sample.paste(im, (0, i * h))
    pal = sample.quantize(colors=colors, method=Image.Quantize.MEDIANCUT)
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
