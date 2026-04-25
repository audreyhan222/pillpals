from __future__ import annotations

from collections import deque
from pathlib import Path
from typing import Iterable

from PIL import Image


REPO_ROOT = Path(__file__).resolve().parents[1]
SOURCE_IMAGES = {
    "cat": Path(
        r"C:\Users\dabro\.cursor\projects\c-Users-dabro-OneDrive-Documents-GitHub-pillpals\assets\c__Users_dabro_AppData_Roaming_Cursor_User_workspaceStorage_686ea93a76e533583c971ffb723b84e0_images_ezgif-81382bcfde31127a-6c425604-39ae-4c39-a43e-c853ba75d3b0.png"
    ),
    "penguin": Path(
        r"C:\Users\dabro\.cursor\projects\c-Users-dabro-OneDrive-Documents-GitHub-pillpals\assets\c__Users_dabro_AppData_Roaming_Cursor_User_workspaceStorage_686ea93a76e533583c971ffb723b84e0_images_ezgif-2a44720e67d72095-282a1d5d-7355-4b9e-b3d8-2a159edc1c9c.png"
    ),
    "bunny": Path(
        r"C:\Users\dabro\.cursor\projects\c-Users-dabro-OneDrive-Documents-GitHub-pillpals\assets\c__Users_dabro_AppData_Roaming_Cursor_User_workspaceStorage_686ea93a76e533583c971ffb723b84e0_images_ezgif-2268eeb88b9699d0-230e3d21-272f-4f1e-9335-721aa357d4ce.png"
    ),
}

EXPRESSION_ORDER = ["neutral", "happy", "sad", "depressed"]


def neighbors(x: int, y: int, width: int, height: int) -> Iterable[tuple[int, int]]:
    if x > 0:
        yield x - 1, y
    if x < width - 1:
        yield x + 1, y
    if y > 0:
        yield x, y - 1
    if y < height - 1:
        yield x, y + 1


def largest_component_bbox(mask: list[list[bool]]) -> tuple[int, int, int, int] | None:
    height = len(mask)
    width = len(mask[0]) if height else 0
    visited = [[False] * width for _ in range(height)]

    best_bbox = None
    best_area = -1

    for y in range(height):
        for x in range(width):
            if not mask[y][x] or visited[y][x]:
                continue

            q = deque([(x, y)])
            visited[y][x] = True
            min_x = max_x = x
            min_y = max_y = y
            count = 0

            while q:
                cx, cy = q.popleft()
                count += 1
                min_x = min(min_x, cx)
                max_x = max(max_x, cx)
                min_y = min(min_y, cy)
                max_y = max(max_y, cy)
                for nx, ny in neighbors(cx, cy, width, height):
                    if mask[ny][nx] and not visited[ny][nx]:
                        visited[ny][nx] = True
                        q.append((nx, ny))

            if count > best_area:
                best_area = count
                best_bbox = (min_x, min_y, max_x + 1, max_y + 1)

    return best_bbox


def crop_expression(image: Image.Image, col: int, row: int, padding: int = 10) -> Image.Image:
    w, h = image.size
    tile_w = w // 2
    tile_h = h // 2
    tile = image.crop((col * tile_w, row * tile_h, (col + 1) * tile_w, (row + 1) * tile_h))
    alpha = tile.split()[-1]

    px = alpha.load()
    mask = [[px[x, y] > 6 for x in range(tile_w)] for y in range(tile_h)]
    bbox = largest_component_bbox(mask)
    if bbox is None:
        return tile

    left, top, right, bottom = bbox
    left = max(0, left - padding)
    top = max(0, top - padding)
    right = min(tile_w, right + padding)
    bottom = min(tile_h, bottom + padding)

    return tile.crop((left, top, right, bottom))


def main() -> None:
    out_root = REPO_ROOT / "assets" / "pals"
    out_root.mkdir(parents=True, exist_ok=True)

    for pal_name, source_path in SOURCE_IMAGES.items():
        if not source_path.exists():
            raise FileNotFoundError(f"Source image not found: {source_path}")

        pal_out_dir = out_root / pal_name
        pal_out_dir.mkdir(parents=True, exist_ok=True)
        for stale_png in pal_out_dir.glob("*.png"):
            stale_png.unlink()

        image = Image.open(source_path).convert("RGBA")
        positions = [(0, 0), (1, 0), (0, 1), (1, 1)]

        for index, (col, row) in enumerate(positions):
            expression = EXPRESSION_ORDER[index]
            cropped = crop_expression(image, col, row)
            out_path = pal_out_dir / f"{expression}.png"
            cropped.save(out_path, format="PNG")
            print(f"Wrote {out_path.relative_to(REPO_ROOT)}")


if __name__ == "__main__":
    main()
