#!/usr/bin/env python3
"""Render and byte-check the deterministic j3w1zsh PNG from its SVG contract."""

from __future__ import annotations

import argparse
import hashlib
import struct
import sys
import zlib
from pathlib import Path
from xml.etree import ElementTree


GLYPHS = {
    ">": ("10000", "01000", "00100", "00010", "00100", "01000", "10000"),
    "_": ("00000", "00000", "00000", "00000", "00000", "00000", "11111"),
    "j": ("00110", "00000", "00110", "00110", "00110", "10110", "01100"),
    "3": ("11110", "00010", "00010", "01110", "00010", "00010", "11110"),
    "w": ("10001", "10001", "10001", "10101", "10101", "10101", "01010"),
    "1": ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
    "z": ("11111", "00001", "00010", "00100", "01000", "10000", "11111"),
    "s": ("01111", "10000", "10000", "01110", "00001", "00001", "11110"),
    "h": ("10000", "10000", "10000", "11110", "10001", "10001", "10001"),
}


def hex_color(value: str) -> tuple[int, int, int]:
    if len(value) != 7 or not value.startswith("#"):
        raise ValueError(f"invalid SVG color: {value}")
    return tuple(int(value[index : index + 2], 16) for index in (1, 3, 5))


def svg_contract(svg_path: Path) -> dict[str, object]:
    root = ElementTree.parse(svg_path).getroot()
    namespace = "{http://www.w3.org/2000/svg}"
    if root.get("width") != "512" or root.get("height") != "512":
        raise ValueError("brand SVG must be exactly 512 by 512")
    elements = {element.get("id"): element for element in root.iter() if element.get("id")}
    for required in ("render-contract", "background", "terminal-frame", "terminal-bar", "framework-spine", "prompt", "wordmark"):
        if required not in elements:
            raise ValueError(f"brand SVG is missing #{required}")
    if (elements["render-contract"].text or "").strip() != "j3w1zsh-brand-v1":
        raise ValueError("unsupported brand render contract")
    if (elements["prompt"].text or "") != ">_" or (elements["wordmark"].text or "") != "j3w1zsh":
        raise ValueError("brand SVG prompt or lowercase wordmark changed")
    if root.tag != f"{namespace}svg":
        raise ValueError("brand source is not SVG")
    return {
        "background": hex_color(elements["background"].get("fill", "")),
        "blood": hex_color(elements["terminal-frame"].get("stroke", "")),
        "bright": hex_color(elements["framework-spine"].get("stroke", "")),
        "foreground": hex_color(elements["wordmark"].get("fill", "")),
        "source_sha256": hashlib.sha256(svg_path.read_bytes()).hexdigest(),
    }


def render_pixels(contract: dict[str, object]) -> bytearray:
    width = height = 512
    background = contract["background"]
    pixels = bytearray(background * (width * height))  # type: ignore[operator]

    def set_pixel(x: int, y: int, color: tuple[int, int, int]) -> None:
        if 0 <= x < width and 0 <= y < height:
            offset = (y * width + x) * 3
            pixels[offset : offset + 3] = bytes(color)

    def rectangle(x: int, y: int, w: int, h: int, color: tuple[int, int, int]) -> None:
        for row in range(max(0, y), min(height, y + h)):
            start = (row * width + max(0, x)) * 3
            end = (row * width + min(width, x + w)) * 3
            pixels[start:end] = bytes(color) * max(0, min(width, x + w) - max(0, x))

    blood = contract["blood"]
    bright = contract["bright"]
    foreground = contract["foreground"]
    # Terminal frame and header.
    rectangle(52, 58, 408, 14, blood)  # type: ignore[arg-type]
    rectangle(52, 344, 408, 14, blood)  # type: ignore[arg-type]
    rectangle(52, 58, 14, 300, blood)  # type: ignore[arg-type]
    rectangle(446, 58, 14, 300, blood)  # type: ignore[arg-type]
    rectangle(52, 58, 408, 52, blood)  # type: ignore[arg-type]
    rectangle(80, 76, 16, 16, background)  # type: ignore[arg-type]
    rectangle(108, 76, 16, 16, bright)  # type: ignore[arg-type]
    rectangle(136, 76, 16, 16, foreground)  # type: ignore[arg-type]
    # Framework spine.
    rectangle(251, 116, 10, 204, bright)  # type: ignore[arg-type]
    for y in (149, 209, 269):
        rectangle(218, y, 76, 10, bright)  # type: ignore[arg-type]

    def draw_text(text: str, x: int, y: int, scale: int, color: tuple[int, int, int], spacing: int) -> None:
        cursor = x
        for character in text:
            glyph = GLYPHS[character]
            for row, bits in enumerate(glyph):
                for column, bit in enumerate(bits):
                    if bit == "1":
                        rectangle(cursor + column * scale, y + row * scale, scale, scale, color)
            cursor += 5 * scale + spacing

    draw_text(">_", 82, 142, 9, foreground, 12)  # type: ignore[arg-type]
    draw_text("j3w1zsh", 67, 378, 7, foreground, 7)  # type: ignore[arg-type]
    rectangle(52, 468, 408, 8, bright)  # type: ignore[arg-type]
    # A single center diamond connects terminal and framework ideas.
    for delta in range(12):
        for x in range(256 - delta, 257 + delta):
            set_pixel(x, 334 + delta, bright)  # type: ignore[arg-type]
            set_pixel(x, 357 - delta, bright)  # type: ignore[arg-type]
    return pixels


def png_chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def render_png(svg_path: Path) -> bytes:
    contract = svg_contract(svg_path)
    pixels = render_pixels(contract)
    rows = b"".join(b"\x00" + pixels[row * 512 * 3 : (row + 1) * 512 * 3] for row in range(512))
    signature = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", 512, 512, 8, 2, 0, 0, 0)
    source = f"svg-sha256={contract['source_sha256']}".encode("ascii")
    return signature + png_chunk(b"IHDR", ihdr) + png_chunk(b"tEXt", b"j3w1zsh\x00" + source) + png_chunk(b"IDAT", zlib.compress(rows, 9)) + png_chunk(b"IEND", b"")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail unless the committed PNG is byte-exact")
    parser.add_argument("--svg", type=Path, default=Path("assets/brand/j3w1zsh.svg"))
    parser.add_argument("--png", type=Path, default=Path("assets/brand/j3w1zsh.png"))
    args = parser.parse_args()
    expected = render_png(args.svg)
    if args.check:
        if not args.png.is_file() or args.png.read_bytes() != expected:
            print(f"brand PNG does not match {args.svg}", file=sys.stderr)
            return 1
        print("Brand SVG/PNG render contract passed.")
        return 0
    args.png.parent.mkdir(parents=True, exist_ok=True)
    args.png.write_bytes(expected)
    print(f"Rendered {args.png} from {args.svg}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
