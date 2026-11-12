"""Higher-density painterly sprite canvases, without moving their footprints.

The earlier output is built in memory as the geometry reference; the larger
image is rebuilt from the original painting, not enlarged from that output.
Aligning its visible bounds to the old canvas preserves the sprite's apparent
size and foot anchor when the game divides its visual scale by DETAIL_FACTOR.
"""
from PIL import Image

DETAIL_FACTOR = 3


def align_to_legacy(legacy, detailed):
    legacy = legacy.convert("RGBA")
    detailed = detailed.convert("RGBA")
    expected = tuple(side * DETAIL_FACTOR for side in legacy.size)
    if detailed.size != expected:
        raise ValueError("detail canvas %s does not match %s" % (detailed.size, expected))
    low_bounds = legacy.getchannel("A").getbbox()
    high_bounds = detailed.getchannel("A").getbbox()
    if low_bounds is None or high_bounds is None:
        raise ValueError("cannot align an empty prop")
    target = ((low_bounds[2] - low_bounds[0]) * DETAIL_FACTOR,
              (low_bounds[3] - low_bounds[1]) * DETAIL_FACTOR)
    visible = detailed.crop(high_bounds).resize(target, Image.Resampling.LANCZOS)
    result = Image.new("RGBA", expected)
    result.alpha_composite(visible, (low_bounds[0] * DETAIL_FACTOR,
                                     low_bounds[1] * DETAIL_FACTOR))
    return result


def detail_size(size):
    return tuple(side * DETAIL_FACTOR for side in size)
