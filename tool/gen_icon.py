import zlib, struct, os

def write_png(path, size):
    w = h = size
    rows = []
    for y in range(h):
        row = bytearray([0])
        ny = (y / (h - 1)) * 2 - 1
        for x in range(w):
            nx = (x / (w - 1)) * 2 - 1
            r, g, b, a = 10, 14, 26, 255
            in_shield = False
            if -0.68 <= ny <= 0.75:
                max_x = 0.58 if ny < 0.05 else 0.58 * (1.0 - ((ny - 0.05) / 0.70) * 0.95)
                if abs(nx) <= max_x:
                    in_shield = True
            if in_shield:
                in_inner = False
                if -0.50 <= ny <= 0.56:
                    imax_x = 0.40 if ny < 0.05 else 0.40 * (1.0 - ((ny - 0.05) / 0.51) * 0.95)
                    if abs(nx) <= imax_x:
                        in_inner = True
                gt = (ny + 0.68) / 1.43
                sr = int(124 * gt)
                sg = int(229 * (1 - gt) + 77 * gt)
                sb = 255
                if not in_inner or (nx * nx + (ny + 0.05) * (ny + 0.05) < 0.035):
                    r, g, b = sr, sg, sb
                else:
                    r, g, b = 19, 26, 46
            row.extend([r, g, b, a])
        rows.append(bytes(row))
    raw = b"".join(rows)
    def chunk(tag, data):
        return struct.pack("!I", len(data)) + tag + data + struct.pack("!I", zlib.crc32(tag + data) & 0xffffffff)
    ihdr = struct.pack("!IIBBBBB", w, h, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)

for folder, sz in [("mipmap-mdpi", 48), ("mipmap-hdpi", 72), ("mipmap-xhdpi", 96), ("mipmap-xxhdpi", 144), ("mipmap-xxxhdpi", 192)]:
    write_png(f"android/app/src/main/res/{folder}/ic_launcher.png", sz)
print("Kavach Shield icons generated!")
