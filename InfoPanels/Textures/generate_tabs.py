#!/usr/bin/env python3
"""
Generate tab-active.tga and tab-inactive.tga for InfoPanels Editor tabs.
Target: visually match Blizzard talent window tab style (WoW 11.x/12.x).
Output: 256x32 RGBA TGA files.
"""

import struct
import os

WIDTH  = 256
HEIGHT = 32
CORNER_RADIUS = 4  # px rounded corner at top-left / top-right

def lerp(a, b, t):
    return int(a + (b - a) * t)

def make_pixel(r, g, b, a=255):
    return (r, g, b, a)

def in_corner(x, y, width, height, radius):
    """Return True if (x,y) is in the cut corner region (top-left or top-right)."""
    # Top-left corner
    if x < radius and y < radius:
        dx = radius - 1 - x
        dy = radius - 1 - y
        if dx * dx + dy * dy > (radius - 0.5) ** 2:
            return True
    # Top-right corner
    if x >= width - radius and y < radius:
        dx = x - (width - radius)
        dy = radius - 1 - y
        if dx * dx + dy * dy > (radius - 0.5) ** 2:
            return True
    return False

def generate_active(width, height):
    """Selected tab: lighter warm gray-brown with gold top edge."""
    pixels = []
    for row in range(height):
        # row 0 = top of image
        y = row
        t = y / (height - 1)  # 0 = top, 1 = bottom
        # Background gradient: warm khaki/brown matching Blizzard active tab
        r_bg = lerp(100, 125, t)
        g_bg = lerp(92, 115, t)
        b_bg = lerp(75, 95, t)

        for col in range(width):
            x = col
            a = 255

            if in_corner(x, y, width, height, CORNER_RADIUS):
                pixels.append(make_pixel(0, 0, 0, 0))
                continue

            # Top edge: 2px bright gold line
            if y == 0:
                pixels.append(make_pixel(210, 175, 65, 255))
                continue
            if y == 1:
                pixels.append(make_pixel(185, 155, 55, 255))
                continue

            # Left/right 1px border
            if x == 0 or x == width - 1:
                pixels.append(make_pixel(70, 64, 52, 255))
                continue

            pixels.append(make_pixel(r_bg, g_bg, b_bg, 255))

    return pixels

def generate_inactive(width, height):
    """Inactive tab: darker, muted, subtle border."""
    pixels = []
    for row in range(height):
        y = row
        t = y / (height - 1)
        # Background gradient: very dark brown-black matching Blizzard inactive tab
        r_bg = lerp(32, 45, t)
        g_bg = lerp(30, 42, t)
        b_bg = lerp(26, 36, t)

        for col in range(width):
            x = col
            a = 255

            if in_corner(x, y, width, height, CORNER_RADIUS):
                pixels.append(make_pixel(0, 0, 0, 0))
                continue

            # Top edge: 1px subtle border
            if y == 0:
                pixels.append(make_pixel(55, 50, 42, 255))
                continue

            # Bottom separator
            if y == height - 1:
                pixels.append(make_pixel(22, 20, 17, 255))
                continue

            # Left/right 1px border
            if x == 0 or x == width - 1:
                pixels.append(make_pixel(25, 23, 20, 255))
                continue

            pixels.append(make_pixel(r_bg, g_bg, b_bg, 255))

    return pixels

def write_tga(path, width, height, pixels):
    """Write an uncompressed 32-bit RGBA TGA file (bottom-up row order)."""
    # TGA header: 18 bytes
    header = struct.pack(
        '<BBBHHBHHHHBB',
        0,      # ID length
        0,      # color map type (none)
        2,      # image type: uncompressed true-color
        0, 0,   # color map origin, length
        0,      # color map entry size
        0, 0,   # X origin, Y origin
        width,
        height,
        32,     # bits per pixel
        0x28    # image descriptor: top-left origin bit (bit5=1) | 8 alpha bits
    )

    # Pixels in top-to-bottom order since we set origin bit in descriptor.
    # TGA stores BGRA.
    with open(path, 'wb') as f:
        f.write(header)
        for (r, g, b, a) in pixels:
            f.write(struct.pack('BBBB', b, g, r, a))

    print(f"Written: {path} ({width}x{height}, {len(pixels)} pixels)")

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))

    active_path   = os.path.join(script_dir, "tab-active.tga")
    inactive_path = os.path.join(script_dir, "tab-inactive.tga")

    active_pixels   = generate_active(WIDTH, HEIGHT)
    inactive_pixels = generate_inactive(WIDTH, HEIGHT)

    write_tga(active_path,   WIDTH, HEIGHT, active_pixels)
    write_tga(inactive_path, WIDTH, HEIGHT, inactive_pixels)

    print("Done.")

if __name__ == "__main__":
    main()
