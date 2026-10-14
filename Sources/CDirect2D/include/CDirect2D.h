// Direct2D and DirectWrite behind a small C interface, so Swift can draw on Windows without COM.
// One canvas draws one frame at a time into a premultiplied BGRA bitmap that layered windows can show.
#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MGCanvas MGCanvas;

/// Path commands. Each takes its points, in order, from the path's point array:
/// move 1, line 1, quad 2 (control, end), cubic 3 (control, control, end), close 0.
enum { MG_MOVE = 0, MG_LINE = 1, MG_QUAD = 2, MG_CUBIC = 3, MG_CLOSE = 4 };
enum { MG_CAP_BUTT = 0, MG_CAP_ROUND = 1, MG_CAP_SQUARE = 2 };
enum { MG_JOIN_MITER = 0, MG_JOIN_ROUND = 1, MG_JOIN_BEVEL = 2 };

typedef struct {
    const uint8_t *ops;
    int count;
    const float *points;   // x, y pairs
} MGPath;

/// x' = a·x + c·y + tx, y' = b·x + d·y + ty
typedef struct { float a, b, c, d, tx, ty; } MGTransform;
typedef struct { float r, g, b, a; } MGColor;

MGCanvas *mg_canvas_create(void);
void mg_canvas_destroy(MGCanvas *canvas);

/// Starts a frame of `width` × `height` pixels, cleared to transparent. Returns 0 on failure.
int mg_canvas_begin(MGCanvas *canvas, int width, int height);
/// Finishes the frame. Returns 0 if it couldn't be drawn (the next frame starts over).
int mg_canvas_end(MGCanvas *canvas);
/// A memory DC holding the finished frame, for UpdateLayeredWindow. Valid until the next begin.
void *mg_canvas_dc(MGCanvas *canvas);
/// The finished frame's pixels (premultiplied BGRA, top row first), `stride` bytes per row.
const void *mg_canvas_pixels(MGCanvas *canvas, int *stride);
/// Writes the finished frame to a PNG file. Returns 0 on failure.
int mg_canvas_save_png(MGCanvas *canvas, const uint16_t *path);

/// Fills a path given in pixels, non-zero winding.
void mg_fill(MGCanvas *canvas, MGPath path, MGColor color);
/// Fills the ellipse inside a rectangle given in user space; `m` maps user space to pixels.
void mg_fill_ellipse(MGCanvas *canvas, float x, float y, float width, float height, MGTransform m, MGColor color);
/// Fills a rectangle given in user space; `m` maps user space to pixels.
void mg_fill_rect(MGCanvas *canvas, float x, float y, float width, float height, MGTransform m, MGColor color);
/// Strokes a path given in user space; `m` maps user space to pixels (and shapes the pen with it).
void mg_stroke(MGCanvas *canvas, MGPath path, MGTransform m, float width, int cap, int join, MGColor color);
/// Restricts drawing to a path given in pixels, until the matching mg_pop_clip.
void mg_push_clip(MGCanvas *canvas, MGPath path);
void mg_pop_clip(MGCanvas *canvas);

/// Draws heavy letters with a white outline `outline` points wide, centred on the origin of `m`
/// (a user space whose y axis points up).
void mg_text(MGCanvas *canvas, const uint16_t *utf16, int length, float size, MGTransform m, MGColor color, float outline);

#ifdef __cplusplus
}
#endif
