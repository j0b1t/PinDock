#!/usr/bin/env python3
"""Assemble a palette-quantized, scaled GIF from PNG frames.

Window captures are RGBA with a transparent (or black) surround. The GIF
keeps that surround transparent so GitHub light/dark READMEs don't show a
black box behind the bubble / app window.
"""
import glob
import os
import sys

from PIL import Image

# Magenta key — not used in PinDock chrome. Becomes the GIF transparent index.
KEY = (255, 0, 255)
# Drop window drop-shadow so it doesn't become a black halo on the README.
ALPHA_CUTOFF = 96


def content_bbox(im: Image.Image):
    mask = im.getchannel("A").point(lambda a: 255 if a >= ALPHA_CUTOFF else 0)
    return mask.getbbox()


def flatten_key(im: Image.Image) -> Image.Image:
    """RGB image: opaque UI pixels, KEY where the capture was empty."""
    mask = im.getchannel("A").point(lambda a: 255 if a >= ALPHA_CUTOFF else 0)
    rgb = Image.new("RGB", im.size, KEY)
    rgb.paste(im.convert("RGB"), mask=mask)
    return rgb


def main() -> None:
    if len(sys.argv) < 3:
        print(
            "usage: make_gif.py <framedir> <out.gif> [max_width] [duration_ms] [colors]",
            file=sys.stderr,
        )
        sys.exit(2)
    framedir, dest = sys.argv[1], sys.argv[2]
    max_width = int(sys.argv[3]) if len(sys.argv) > 3 else 1440
    duration = int(sys.argv[4]) if len(sys.argv) > 4 else 90
    colors = int(sys.argv[5]) if len(sys.argv) > 5 else 256

    paths = sorted(glob.glob(os.path.join(framedir, "frame-*.png")))
    if not paths:
        print(f"no frames in {framedir}", file=sys.stderr)
        sys.exit(1)

    raw = [Image.open(path).convert("RGBA") for path in paths]

    boxes = [content_bbox(im) for im in raw]
    boxes = [b for b in boxes if b]
    if not boxes:
        print("frames have no opaque pixels", file=sys.stderr)
        sys.exit(1)
    left = min(b[0] for b in boxes)
    top = min(b[1] for b in boxes)
    right = max(b[2] for b in boxes)
    bottom = max(b[3] for b in boxes)
    pad = 2
    left = max(0, left - pad)
    top = max(0, top - pad)
    right = min(raw[0].width, right + pad)
    bottom = min(raw[0].height, bottom + pad)
    crop = (left, top, right, bottom)

    images = []
    for im in raw:
        frame = im.crop(crop)
        if frame.width > max_width:
            h = max(1, int(round(frame.height * (max_width / frame.width))))
            frame = frame.resize((max_width, h), Image.Resampling.LANCZOS)
        images.append(flatten_key(frame))

    w0, h0 = images[0].size
    images = [
        im.resize((w0, h0), Image.Resampling.LANCZOS) if im.size != (w0, h0) else im
        for im in images
    ]

    idxs = [0, len(images) // 2, len(images) - 1]
    picks = [images[i] for i in idxs]
    sample = Image.new("RGB", (w0, h0 * len(picks)), KEY)
    for i, im in enumerate(picks):
        sample.paste(im, (0, i * h0))
    # Reserve one palette slot for the transparent key.
    pal = sample.quantize(colors=max(2, colors - 1), method=Image.Quantize.MEDIANCUT)
    key_idx = Image.new("RGB", (1, 1), KEY).quantize(palette=pal).getpixel((0, 0))
    quantized = [im.quantize(palette=pal, dither=Image.Dither.NONE) for im in images]

    quantized[0].save(
        dest,
        save_all=True,
        append_images=quantized[1:],
        duration=duration,
        loop=0,
        optimize=False,
        disposal=2,
        transparency=key_idx,
    )
    kb = os.path.getsize(dest) / 1024
    print(f"wrote {dest} ({kb:.0f}K, {len(quantized)} frames, transparent={key_idx})")


if __name__ == "__main__":
    main()
