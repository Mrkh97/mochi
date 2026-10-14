#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <d2d1.h>
#include <dwrite.h>
#include <wincodec.h>

#include <algorithm>
#include <string>
#include <unordered_map>
#include <vector>

#include "CDirect2D.h"

template <class T> static void release(T *&p) {
    if (p) { p->Release(); p = nullptr; }
}

namespace {

struct Glyphs {
    ID2D1PathGeometry *outline = nullptr;
    D2D1_RECT_F bounds{};
};

struct Clip {
    ID2D1Layer *layer;
    ID2D1Geometry *geometry;
};

D2D1_MATRIX_3X2_F matrix(MGTransform m) {
    // CoreGraphics: x' = a·x + c·y + tx. Direct2D multiplies row vectors, so the same numbers line up.
    return D2D1::Matrix3x2F(m.a, m.b, m.c, m.d, m.tx, m.ty);
}

D2D1_COLOR_F color(MGColor c) { return D2D1::ColorF(c.r, c.g, c.b, c.a); }

} // namespace

struct MGCanvas {
    ID2D1Factory *factory = nullptr;
    IDWriteFactory *dwrite = nullptr;
    ID2D1DCRenderTarget *target = nullptr;
    ID2D1SolidColorBrush *brush = nullptr;
    ID2D1StrokeStyle *styles[3][3] = {};
    HDC dc = nullptr;
    HBITMAP bitmap = nullptr;
    HGDIOBJ initialBitmap = nullptr;
    void *bits = nullptr;
    int bitmapWidth = 0, bitmapHeight = 0;
    int width = 0, height = 0;
    bool drawing = false;
    std::vector<Clip> clips;
    IDWriteFontFace *face = nullptr;
    IDWriteFontFace *symbols = nullptr;
    std::unordered_map<std::wstring, Glyphs> text;

    bool ensureTarget() {
        if (target) return true;
        auto props = D2D1::RenderTargetProperties(
            D2D1_RENDER_TARGET_TYPE_SOFTWARE,
            D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED));
        if (FAILED(factory->CreateDCRenderTarget(&props, &target))) return false;
        if (FAILED(target->CreateSolidColorBrush(D2D1::ColorF(0, 0, 0, 1), &brush))) {
            release(target);
            return false;
        }
        return true;
    }

    void dropTarget() {
        release(brush);
        release(target);
    }

    bool ensureBitmap(int w, int h) {
        if (w <= bitmapWidth && h <= bitmapHeight) return true;
        int bw = std::max(w, bitmapWidth), bh = std::max(h, bitmapHeight);
        BITMAPINFO info{};
        info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        info.bmiHeader.biWidth = bw;
        info.bmiHeader.biHeight = -bh;   // top-down
        info.bmiHeader.biPlanes = 1;
        info.bmiHeader.biBitCount = 32;
        info.bmiHeader.biCompression = BI_RGB;
        void *newBits = nullptr;
        HBITMAP b = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &newBits, nullptr, 0);
        if (!b) return false;
        HGDIOBJ old = SelectObject(dc, b);
        if (!initialBitmap) initialBitmap = old;
        if (bitmap) DeleteObject(bitmap);
        bitmap = b;
        bits = newBits;
        bitmapWidth = bw;
        bitmapHeight = bh;
        return true;
    }

    ID2D1StrokeStyle *style(int cap, int join) {
        cap = std::clamp(cap, 0, 2);
        join = std::clamp(join, 0, 2);
        if (!styles[cap][join]) {
            static const D2D1_CAP_STYLE caps[] = {D2D1_CAP_STYLE_FLAT, D2D1_CAP_STYLE_ROUND, D2D1_CAP_STYLE_SQUARE};
            static const D2D1_LINE_JOIN joins[] = {D2D1_LINE_JOIN_MITER_OR_BEVEL, D2D1_LINE_JOIN_ROUND, D2D1_LINE_JOIN_BEVEL};
            // A miter limit of 10 is CoreGraphics' default.
            auto props = D2D1::StrokeStyleProperties(caps[cap], caps[cap], caps[cap], joins[join], 10.0f);
            factory->CreateStrokeStyle(props, nullptr, 0, &styles[cap][join]);
        }
        return styles[cap][join];
    }

    ID2D1PathGeometry *geometry(MGPath path) {
        ID2D1PathGeometry *g = nullptr;
        if (FAILED(factory->CreatePathGeometry(&g))) return nullptr;
        ID2D1GeometrySink *sink = nullptr;
        if (FAILED(g->Open(&sink))) {
            release(g);
            return nullptr;
        }
        sink->SetFillMode(D2D1_FILL_MODE_WINDING);
        const float *p = path.points;
        bool open = false;
        D2D1_POINT_2F start{}, current{};
        auto begin = [&](D2D1_POINT_2F at) {
            if (open) sink->EndFigure(D2D1_FIGURE_END_OPEN);
            sink->BeginFigure(at, D2D1_FIGURE_BEGIN_FILLED);
            open = true;
            start = at;
        };
        // Drawing from a closed (or not yet started) subpath continues from where it ended.
        auto ensureOpen = [&]() {
            if (!open) begin(current);
        };
        for (int i = 0; i < path.count; i++) {
            switch (path.ops[i]) {
            case MG_MOVE:
                current = D2D1::Point2F(p[0], p[1]);
                begin(current);
                p += 2;
                break;
            case MG_LINE:
                ensureOpen();
                current = D2D1::Point2F(p[0], p[1]);
                sink->AddLine(current);
                p += 2;
                break;
            case MG_QUAD:
                ensureOpen();
                current = D2D1::Point2F(p[2], p[3]);
                sink->AddQuadraticBezier(D2D1::QuadraticBezierSegment(D2D1::Point2F(p[0], p[1]), current));
                p += 4;
                break;
            case MG_CUBIC:
                ensureOpen();
                current = D2D1::Point2F(p[4], p[5]);
                sink->AddBezier(D2D1::BezierSegment(D2D1::Point2F(p[0], p[1]), D2D1::Point2F(p[2], p[3]), current));
                p += 6;
                break;
            case MG_CLOSE:
                if (open) {
                    sink->EndFigure(D2D1_FIGURE_END_CLOSED);
                    open = false;
                    current = start;
                }
                break;
            }
        }
        if (open) sink->EndFigure(D2D1_FIGURE_END_OPEN);
        HRESULT hr = sink->Close();
        release(sink);
        if (FAILED(hr)) release(g);
        return g;
    }

    IDWriteFontFace *makeFace(const wchar_t *family) {
        IDWriteFontCollection *fonts = nullptr;
        if (FAILED(dwrite->GetSystemFontCollection(&fonts))) return nullptr;
        IDWriteFontFace *result = nullptr;
        UINT32 index = 0;
        BOOL exists = FALSE;
        if (SUCCEEDED(fonts->FindFamilyName(family, &index, &exists)) && exists) {
            IDWriteFontFamily *fam = nullptr;
            if (SUCCEEDED(fonts->GetFontFamily(index, &fam))) {
                IDWriteFont *font = nullptr;
                if (SUCCEEDED(fam->GetFirstMatchingFont(DWRITE_FONT_WEIGHT_BLACK, DWRITE_FONT_STRETCH_NORMAL,
                                                        DWRITE_FONT_STYLE_NORMAL, &font))) {
                    font->CreateFontFace(&result);
                    release(font);
                }
                release(fam);
            }
        }
        release(fonts);
        return result;
    }

    /// Letter outlines for a word, built once.
    Glyphs *glyphs(const uint16_t *utf16, int length, float size) {
        std::wstring key(reinterpret_cast<const wchar_t *>(utf16), length);
        key += L'|' + std::to_wstring(size);
        auto found = text.find(key);
        if (found != text.end()) return &found->second;

        if (!face) face = makeFace(L"Segoe UI");
        if (!symbols) symbols = makeFace(L"Segoe UI Symbol");
        std::vector<UINT32> codepoints;
        for (int i = 0; i < length; i++) {
            UINT32 c = utf16[i];
            if (c >= 0xD800 && c < 0xDC00 && i + 1 < length) {
                c = 0x10000 + ((c - 0xD800) << 10) + (utf16[i + 1] - 0xDC00);
                i++;
            }
            codepoints.push_back(c);
        }
        Glyphs result;
        // Use the symbol font for anything the text font lacks (♪).
        IDWriteFontFace *chosen = nullptr;
        std::vector<UINT16> indices(codepoints.size());
        for (IDWriteFontFace *f : {face, symbols}) {
            if (!f || codepoints.empty()) continue;
            f->GetGlyphIndices(codepoints.data(), (UINT32)codepoints.size(), indices.data());
            if (std::find(indices.begin(), indices.end(), 0) == indices.end()) {
                chosen = f;
                break;
            }
        }
        if (chosen) {
            DWRITE_FONT_METRICS fm{};
            chosen->GetMetrics(&fm);
            std::vector<DWRITE_GLYPH_METRICS> gm(indices.size());
            chosen->GetDesignGlyphMetrics(indices.data(), (UINT32)indices.size(), gm.data(), FALSE);
            std::vector<FLOAT> advances(indices.size());
            for (size_t i = 0; i < indices.size(); i++) advances[i] = gm[i].advanceWidth * size / fm.designUnitsPerEm;
            ID2D1PathGeometry *g = nullptr;
            ID2D1GeometrySink *sink = nullptr;
            if (SUCCEEDED(factory->CreatePathGeometry(&g)) && SUCCEEDED(g->Open(&sink))) {
                sink->SetFillMode(D2D1_FILL_MODE_WINDING);
                HRESULT hr = chosen->GetGlyphRunOutline(size, indices.data(), advances.data(), nullptr,
                                                        (UINT32)indices.size(), FALSE, FALSE, sink);
                if (SUCCEEDED(sink->Close()) && SUCCEEDED(hr)) {
                    g->GetBounds(nullptr, &result.bounds);
                    result.outline = g;
                    g = nullptr;
                }
            }
            release(sink);
            release(g);
        }
        return &(text[key] = result);
    }
};

extern "C" {

MGCanvas *mg_canvas_create(void) {
    auto *c = new MGCanvas();
    if (FAILED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, &c->factory)) ||
        FAILED(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
                                   reinterpret_cast<IUnknown **>(&c->dwrite)))) {
        mg_canvas_destroy(c);
        return nullptr;
    }
    c->dc = CreateCompatibleDC(nullptr);
    return c;
}

void mg_canvas_destroy(MGCanvas *c) {
    if (!c) return;
    for (auto &entry : c->text) release(entry.second.outline);
    for (auto &row : c->styles)
        for (auto &s : row) release(s);
    release(c->face);
    release(c->symbols);
    c->dropTarget();
    if (c->dc) {
        if (c->initialBitmap) SelectObject(c->dc, c->initialBitmap);
        DeleteDC(c->dc);
    }
    if (c->bitmap) DeleteObject(c->bitmap);
    release(c->dwrite);
    release(c->factory);
    delete c;
}

int mg_canvas_begin(MGCanvas *c, int w, int h) {
    if (w <= 0 || h <= 0 || !c->ensureBitmap(w, h) || !c->ensureTarget()) return 0;
    RECT r{0, 0, w, h};
    if (FAILED(c->target->BindDC(c->dc, &r))) return 0;
    c->width = w;
    c->height = h;
    c->target->BeginDraw();
    c->drawing = true;
    c->target->SetTransform(D2D1::Matrix3x2F::Identity());
    c->target->Clear(D2D1::ColorF(0, 0, 0, 0));
    return 1;
}

int mg_canvas_end(MGCanvas *c) {
    if (!c->drawing) return 0;
    while (!c->clips.empty()) mg_pop_clip(c);
    HRESULT hr = c->target->EndDraw();
    c->drawing = false;
    if (hr == D2DERR_RECREATE_TARGET) c->dropTarget();
    GdiFlush();
    return SUCCEEDED(hr) ? 1 : 0;
}

void *mg_canvas_dc(MGCanvas *c) { return c->dc; }

const void *mg_canvas_pixels(MGCanvas *c, int *stride) {
    GdiFlush();
    if (stride) *stride = c->bitmapWidth * 4;
    return c->bits;
}

int mg_canvas_save_png(MGCanvas *c, const uint16_t *path) {
    if (!c->bits || c->width <= 0) return 0;
    GdiFlush();
    bool ok = false;
    HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    IWICImagingFactory *wic = nullptr;
    IWICStream *stream = nullptr;
    IWICBitmapEncoder *encoder = nullptr;
    IWICBitmapFrameEncode *frame = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&wic))) &&
        SUCCEEDED(wic->CreateStream(&stream)) &&
        SUCCEEDED(stream->InitializeFromFilename(reinterpret_cast<const wchar_t *>(path), GENERIC_WRITE)) &&
        SUCCEEDED(wic->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder)) &&
        SUCCEEDED(encoder->Initialize(stream, WICBitmapEncoderNoCache)) &&
        SUCCEEDED(encoder->CreateNewFrame(&frame, nullptr)) && SUCCEEDED(frame->Initialize(nullptr)) &&
        SUCCEEDED(frame->SetSize(c->width, c->height))) {
        WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
        frame->SetPixelFormat(&format);
        // PNG stores straight alpha; the bitmap is premultiplied.
        std::vector<uint8_t> row(c->width * 4);
        bool rows = true;
        for (int y = 0; y < c->height && rows; y++) {
            const uint8_t *src = static_cast<const uint8_t *>(c->bits) + (size_t)y * c->bitmapWidth * 4;
            for (int x = 0; x < c->width; x++) {
                uint8_t a = src[x * 4 + 3];
                for (int k = 0; k < 3; k++)
                    row[x * 4 + k] = a ? (uint8_t)std::min(255, src[x * 4 + k] * 255 / a) : 0;
                row[x * 4 + 3] = a;
            }
            rows = SUCCEEDED(frame->WritePixels(1, c->width * 4, (UINT)row.size(), row.data()));
        }
        ok = rows && SUCCEEDED(frame->Commit()) && SUCCEEDED(encoder->Commit());
    }
    release(frame);
    release(encoder);
    release(stream);
    release(wic);
    if (SUCCEEDED(init)) CoUninitialize();
    return ok ? 1 : 0;
}

void mg_fill(MGCanvas *c, MGPath path, MGColor col) {
    if (!c->drawing || path.count == 0) return;
    ID2D1PathGeometry *g = c->geometry(path);
    if (!g) return;
    c->target->SetTransform(D2D1::Matrix3x2F::Identity());
    c->brush->SetColor(color(col));
    c->target->FillGeometry(g, c->brush);
    release(g);
}

void mg_fill_ellipse(MGCanvas *c, float x, float y, float w, float h, MGTransform m, MGColor col) {
    if (!c->drawing) return;
    c->target->SetTransform(matrix(m));
    c->brush->SetColor(color(col));
    c->target->FillEllipse(D2D1::Ellipse(D2D1::Point2F(x + w / 2, y + h / 2), w / 2, h / 2), c->brush);
}

void mg_fill_rect(MGCanvas *c, float x, float y, float w, float h, MGTransform m, MGColor col) {
    if (!c->drawing) return;
    c->target->SetTransform(matrix(m));
    c->brush->SetColor(color(col));
    c->target->FillRectangle(D2D1::RectF(x, y, x + w, y + h), c->brush);
}

void mg_stroke(MGCanvas *c, MGPath path, MGTransform m, float width, int cap, int join, MGColor col) {
    if (!c->drawing || path.count == 0) return;
    ID2D1PathGeometry *g = c->geometry(path);
    if (!g) return;
    c->target->SetTransform(matrix(m));
    c->brush->SetColor(color(col));
    c->target->DrawGeometry(g, c->brush, width, c->style(cap, join));
    release(g);
}

void mg_push_clip(MGCanvas *c, MGPath path) {
    if (!c->drawing) return;
    ID2D1Geometry *g = c->geometry(path);
    if (!g) {
        // Couldn't build it: clip everything away rather than nothing.
        ID2D1RectangleGeometry *none = nullptr;
        c->factory->CreateRectangleGeometry(D2D1::RectF(0, 0, 0, 0), &none);
        g = none;
    }
    ID2D1Layer *layer = nullptr;
    c->target->CreateLayer(nullptr, &layer);
    c->target->SetTransform(D2D1::Matrix3x2F::Identity());
    if (layer && g) c->target->PushLayer(D2D1::LayerParameters(D2D1::InfiniteRect(), g), layer);
    // Pushed or not, it's recorded, so pops stay paired with saveGState/restoreGState.
    c->clips.push_back({layer, g});
}

void mg_pop_clip(MGCanvas *c) {
    if (c->clips.empty()) return;
    Clip clip = c->clips.back();
    c->clips.pop_back();
    if (clip.layer && clip.geometry) c->target->PopLayer();
    release(clip.layer);
    release(clip.geometry);
}

void mg_text(MGCanvas *c, const uint16_t *utf16, int length, float size, MGTransform m, MGColor col, float outline) {
    if (!c->drawing || length == 0) return;
    Glyphs *g = c->glyphs(utf16, length, size);
    if (!g->outline) return;
    float cx = (g->bounds.left + g->bounds.right) / 2, cy = (g->bounds.top + g->bounds.bottom) / 2;
    // Glyph outlines have y pointing down; centre them and flip into the caller's y-up space.
    auto t = D2D1::Matrix3x2F::Translation(-cx, -cy) * D2D1::Matrix3x2F::Scale(1, -1) * matrix(m);
    c->target->SetTransform(t);
    c->brush->SetColor(color(col));
    c->target->FillGeometry(g->outline, c->brush);
    c->brush->SetColor(D2D1::ColorF(1, 1, 1, col.a));
    c->target->DrawGeometry(g->outline, c->brush, outline, c->style(MG_CAP_ROUND, MG_JOIN_ROUND));
}

} // extern "C"
