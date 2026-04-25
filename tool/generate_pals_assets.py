from __future__ import annotations

from pathlib import Path

from PIL import Image


REPO_ROOT = Path(__file__).resolve().parents[1]
SOURCE_GIFS = {
    "cat": REPO_ROOT / "assets" / "pals" / "cat" / "cat.gif",
    "penguin": REPO_ROOT / "assets" / "pals" / "penguin" / "penguin.gif",
    "bunny": REPO_ROOT / "assets" / "pals" / "bunny" / "bunny.gif",
}

EXPRESSION_ORDER = ["neutral", "happy", "sad", "depressed"]
POSITIONS = [(0, 0), (1, 0), (0, 1), (1, 1)]


def _tile_crop(image: Image.Image, col: int, row: int) -> Image.Image:
    tile_w = image.width // 2
    tile_h = image.height // 2
    return image.crop((col * tile_w, row * tile_h, (col + 1) * tile_w, (row + 1) * tile_h))


def _union_bbox(frames: list[Image.Image], alpha_threshold: int = 6) -> tuple[int, int, int, int]:
    left = top = None
    right = bottom = None
    for frame in frames:
        alpha = frame.split()[-1].point(lambda a: 255 if a > alpha_threshold else 0)
        bbox = alpha.getbbox()
        if bbox is None:
            continue
        b_left, b_top, b_right, b_bottom = bbox
        left = b_left if left is None else min(left, b_left)
        top = b_top if top is None else min(top, b_top)
        right = b_right if right is None else max(right, b_right)
        bottom = b_bottom if bottom is None else max(bottom, b_bottom)

    if left is None or top is None or right is None or bottom is None:
        return 0, 0, frames[0].width, frames[0].height
    return left, top, right, bottom


def _crop_frames(frames: list[Image.Image], padding: int = 10) -> list[Image.Image]:
    left, top, right, bottom = _union_bbox(frames)
    left = max(0, left - padding)
    top = max(0, top - padding)
    right = min(frames[0].width, right + padding)
    bottom = min(frames[0].height, bottom + padding)
    return [frame.crop((left, top, right, bottom)) for frame in frames]


def main() -> None:
    out_root = REPO_ROOT / "assets" / "pals"
    out_root.mkdir(parents=True, exist_ok=True)

    for pal_name, source_path in SOURCE_GIFS.items():
        if not source_path.exists():
            raise FileNotFoundError(f"Source gif not found: {source_path}")

        pal_out_dir = out_root / pal_name
        pal_out_dir.mkdir(parents=True, exist_ok=True)
        for stale_asset in pal_out_dir.glob("neutral.*"):
            stale_asset.unlink()
        for stale_asset in pal_out_dir.glob("happy.*"):
            stale_asset.unlink()
        for stale_asset in pal_out_dir.glob("sad.*"):
            stale_asset.unlink()
        for stale_asset in pal_out_dir.glob("depressed.*"):
            stale_asset.unlink()

        with Image.open(source_path) as image:
            frame_count = getattr(image, "n_frames", 1)

            for index, (col, row) in enumerate(POSITIONS):
                expression = EXPRESSION_ORDER[index]
                tiles: list[Image.Image] = []

                for frame_index in range(frame_count):
                    image.seek(frame_index)
                    rgba = image.convert("RGBA")
                    tiles.append(_tile_crop(rgba, col, row))

                cropped_frames = _crop_frames(tiles)
                out_path = pal_out_dir / f"{expression}.gif"
                first, rest = cropped_frames[0], cropped_frames[1:]
                first.save(
                    out_path,
                    format="GIF",
                    save_all=True,
                    append_images=rest,
                    duration=image.info.get("duration", 90),
                    loop=image.info.get("loop", 0),
                    disposal=2,
                )
                print(f"Wrote {out_path.relative_to(REPO_ROOT)}")


if __name__ == "__main__":
    main()
