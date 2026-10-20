; ============================================================================
; GlassToast.ahk — "liquid glass" style notification for AutoHotkey v2
; Part of Windows 11 Key Remapper (MIT License)
;
; GlassToast(title, sub, kind := "ok", holdMs := 5000)
;   kind: "ok" (green check), "warn" (orange !), "info" (blue pause bars),
;         "update" (blue arrow)
; Style, read when each toast is built:
;   GTCFG.position:  TopCenter | TopRight | TopLeft | BottomCenter | BottomRight | BottomLeft
;   GTCFG.animation: Slide | Fade | None
;   GTCFG.glass:      true = frosted glass, false = solid card (no screen capture)
;   GTCFG.solidTheme: "light" | "dark" | "" (= Windows app mode), for the solid card
;
; Design notes (see docs/DEVELOPMENT.md for the full story):
; - Rounded card on the monitor under the mouse (top center by default). It
;   slides in from the nearest edge with a slight overshoot (or fades, or
;   just appears), stays holdMs and leaves the same way. Click to dismiss.
; - The "glass" is a capture of the screen behind the card, blurred at 1/4
;   resolution and slightly saturated. Light/dark theme is picked from the
;   luminance of that background. Without glass the card is solid, in the
;   settings window's colors, and nothing is captured.
; - PERFORMANCE: everything is drawn ONCE. As soon as DWM has the bitmap,
;   every GDI+ object is released (GdiplusShutdown included). The animation
;   only moves/fades the window (UpdateLayeredWindow without a bitmap).
;   When it ends the window is destroyed and the 1 ms timer resolution is
;   restored, so nothing stays in memory between notifications.
; - Per-Monitor DPI Aware v2 is enabled ONLY while the toast is built and
;   animated (thread context is restored afterwards), so the rest of the
;   app (e.g. the settings window) keeps AutoHotkey's normal DPI behavior.
; - AHK variable names are case-insensitive: never use pairs like S/s,
;   W/w, H/h, B/b in the same function (that once scaled the icon by DPI).
; ============================================================================

GTCFG := {holdMs: 5000, inMs: 520, outMs: 300
        , top: 18, h: 64, radius: 22, iconSize: 44          ; top = gap to the screen edge
        , minW: 230, maxW: 400, shadowReach: 36
        , blur: 60, saturation: 1.3
        , position: "TopCenter", animation: "Slide", glass: true, solidTheme: ""}

GT_KINDS := Map("ok", 0xFF30D158, "warn", 0xFFFF9F0A, "info", 0xFF0A84FF, "update", 0xFF0A84FF)

GT_THEMES := {
    dark:  {tint: 0x6618181C, title: 0xFFFFFFFF, sub: 0xCCEBEBF5, sheen: 0x24FFFFFF
          , rimTop: 0x99FFFFFF, rimMid: 0x14FFFFFF, rimBot: 0x4DFFFFFF
          , outline: 0x33000000, accentIcon: 0, shadow: 1},
    light: {tint: 0x99FFFFFF, title: 0xFF2C2C30, sub: 0x8C1C1C1E, sheen: 0x33FFFFFF
          , rimTop: 0xCCFFFFFF, rimMid: 0x26FFFFFF, rimBot: 0x73FFFFFF
          , outline: 0x14000000, accentIcon: 0.22, shadow: 0.55},
    ; Solid cards: same colors as the settings window
    solidDark:  {fill: 0xFF2B2B2B, edge: 0xFF3A3A3A, title: 0xFFF3F3F3, sub: 0xFFABABAB, accentIcon: 0, shadow: 1},
    solidLight: {fill: 0xFFEDE9E2, edge: 0xFFD3CDC3, title: 0xFF26231F, sub: 0xFF5E5850, accentIcon: 0, shadow: 0.55}
}

GT := {phase: "", t0: 0, holdUntil: 0, holdMs: 5000, anim: "Slide"
     , xVis: 0, yVis: 0, xHid: 0, yHid: 0, winW: 0, H: 0, gui: 0, hwnd: 0}

DllCall("LoadLibrary", "str", "winmm", "ptr")      ; keep timeBeginPeriod loaded
OnMessage(0x201, GT_Click)                          ; WM_LBUTTONDOWN -> dismiss
OnExit((*) => GT_Free())

GlassToast(title, sub, kind := "ok", holdMs := 5000) {
    Critical
    global GT, GTCFG, GT_THEMES, GT_KINDS
    GT_Free()                                       ; replace any visible toast
    GT.anim := GTCFG.animation
    oldCtx := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        GT_Build(title, sub, GT_KINDS.Has(kind) ? kind : "ok")
    } finally {
        DllCall("SetThreadDpiAwarenessContext", "ptr", oldCtx, "ptr")
    }
    GT.holdMs := holdMs
    if (GT.anim = "None") {                         ; no animation: show, wait, remove
        GT_Move(GT.xVis, GT.yVis, 255)
        GT.phase := "hold", GT.holdUntil := A_TickCount + holdMs
        SetTimer GT_Step, 50
        return
    }
    GT.phase := "in", GT.t0 := A_TickCount
    GT_HiRes(true)
    SetTimer GT_Step, 10
}

; Where the window rests and where it comes from (window coordinates; the
; card sits `pad` inside the window because of the shadow). Slide comes in
; from the nearest edge: top or bottom for the center, the side otherwise.
GT_Placement(mL, mT, mR, mB, winW, winH, pad, edge, position, anim) {
    cardW := winW - 2 * pad, cardH := winH - 2 * pad
    left := InStr(position, "Left"), right := InStr(position, "Right"), bottom := InStr(position, "Bottom")
    xVis := left ? mL + edge - pad : right ? mR - edge - cardW - pad : mL + (mR - mL - winW) // 2
    yVis := bottom ? mB - edge - cardH - pad : mT + edge - pad
    xHid := xVis, yHid := yVis
    if (anim = "Slide") {
        if left
            xHid := mL - winW
        else if right
            xHid := mR
        else if bottom
            yHid := yVis + Round(cardH * 0.75)      ; rises a little: the taskbar is below
        else
            yHid := mT - winH
    }
    return {xVis: xVis, yVis: yVis, xHid: xHid, yHid: yHid}
}

GT_Move(x, y, alpha) {                              ; no bitmap: DWM reuses the surface
    oldCtx := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    pt := Buffer(8), NumPut("int", Round(x), "int", Round(y), pt)
    blend := (Max(0, Min(255, Round(alpha))) << 16) | (1 << 24)
    DllCall("UpdateLayeredWindow", "ptr", GT.hwnd, "ptr", 0, "ptr", pt, "ptr", 0
          , "ptr", 0, "ptr", 0, "uint", 0, "uint*", blend, "uint", 2)
    DllCall("SetThreadDpiAwarenessContext", "ptr", oldCtx, "ptr")
}

GT_Build(title, sub, kind) {
    global GT, GTCFG, GT_THEMES, GT_KINDS

    ; Monitor under the mouse, its work area, its full area and its scale
    mon := GT_MouseMonitor()
    MonitorGetWorkArea(mon, &mL, &mT, &mR, &mB)
    MonitorGet(mon, &fL, &fT, &fR, &fB)
    S := GT_MonitorDpi(mon) / 96
    ch := Round(GTCFG.h * S), R := Round(GTCFG.radius * S)
    isz := Round(GTCFG.iconSize * S), m := (ch - isz) / 2
    PAD := Round((GTCFG.shadowReach + 10) * S)
    canvW := Round(GTCFG.maxW * S) + 2 * PAD, canvH := ch + 2 * PAD

    ; GDI+ only lives while drawing
    DllCall("LoadLibrary", "str", "gdiplus", "ptr")
    si := Buffer(24, 0), NumPut("uint", 1, si)
    tok := 0
    DllCall("gdiplus\GdiplusStartup", "ptr*", &tok, "ptr", si, "ptr", 0)

    ; Canvas (32-bit DIB for UpdateLayeredWindow)
    bi := Buffer(40, 0)
    NumPut("uint", 40, bi, 0), NumPut("int", canvW, bi, 4), NumPut("int", -canvH, bi, 8)
    NumPut("ushort", 1, bi, 12), NumPut("ushort", 32, bi, 14)
    hdc := DllCall("CreateCompatibleDC", "ptr", 0, "ptr")
    bits := 0
    hbm := DllCall("CreateDIBSection", "ptr", hdc, "ptr", bi, "uint", 0, "ptr*", &bits, "ptr", 0, "uint", 0, "ptr")
    obm := DllCall("SelectObject", "ptr", hdc, "ptr", hbm, "ptr")
    g := 0
    DllCall("gdiplus\GdipCreateFromHDC", "ptr", hdc, "ptr*", &g)
    GT_Quality(g)

    ; Fonts and string format
    famR := GT_Family("Segoe UI"), famSB := GT_Family("Segoe UI Semibold")
    fam := famSB ? famSB : famR, st := famSB ? 0 : 1
    fTitle := GT_Font(fam, 15 * S, st), fSub := GT_Font(famR, 13 * S, 0)
    fmtL := 0
    DllCall("gdiplus\GdipCreateStringFormat", "int", 0x1000, "int", 0, "ptr*", &fmtL)   ; NoWrap
    DllCall("gdiplus\GdipSetStringFormatLineAlign", "ptr", fmtL, "int", 1)
    DllCall("gdiplus\GdipSetStringFormatTrimming", "ptr", fmtL, "int", 3)                   ; ellipsis

    ; Card width from the text, position on screen
    textX := ch - m + 13 * S
    pw := textX + Max(GT_MeasureW(g, title, fTitle, fmtL), GT_MeasureW(g, sub, fSub, fmtL)) + 24 * S
    pw := Round(Max(GTCFG.minW * S, Min(GTCFG.maxW * S, pw)))
    winW := pw + 2 * PAD
    pos := GT_Placement(mL, mT, mR, mB, winW, canvH, PAD, Round(GTCFG.top * S), GTCFG.position, GT.anim)
    GT.xVis := pos.xVis, GT.yVis := pos.yVis, GT.xHid := pos.xHid, GT.yHid := pos.yHid
    GT.winW := winW, GT.H := canvH

    ; Background: capture the card area (final position) and blur it. The
    ; margin is larger than the blur radius (clean edges), but the capture
    ; stays on this monitor.
    glass := GTCFG.glass, blurred := 0, tex := 0
    if glass {
        marg := Round(90 * S)
        cardX := GT.xVis + PAD, cardY := GT.yVis + PAD
        capX := Max(fL, cardX - marg), capY := Max(fT, cardY - marg)
        capW := Min(fR, cardX + pw + marg) - capX, capH := Min(fB, cardY + ch + marg) - capY
        th := GT_THEMES.dark
        blurred := GT_CaptureBlur(capX, capY, capW, capH, S, cardX - capX, cardY - capY, ch, pw, &th)
        DllCall("gdiplus\GdipCreateTexture", "ptr", blurred, "int", 0, "ptr*", &tex)
        DllCall("gdiplus\GdipTranslateTextureTransform", "ptr", tex
              , "float", capX - GT.xVis, "float", capY - GT.yVis, "int", 0)
    } else
        th := GT_SolidLight() ? GT_THEMES.solidLight : GT_THEMES.solidDark

    ; --- Draw (once) ---
    x := PAD, y := PAD, w := pw, h := ch
    DllCall("gdiplus\GdipGraphicsClear", "ptr", g, "uint", 0)
    card := GT_RoundPath(x, y, w, h, R)

    ; Shadow only outside the card
    DllCall("gdiplus\GdipSetClipPath", "ptr", g, "ptr", card, "int", 4)   ; CombineModeExclude
    GT_Shadow(g, x, y, w, h, R, S, th.shadow)
    DllCall("gdiplus\GdipResetClip", "ptr", g)

    ; Glass + tint + top sheen, or a solid card
    if glass {
        DllCall("gdiplus\GdipFillPath", "ptr", g, "ptr", tex, "ptr", card)
        GT_FillPath(g, card, th.tint)
        b := GT_Grad(x, y, w, h, [th.sheen, 0x00FFFFFF, 0x00FFFFFF], [0, 0.5, 1])
        DllCall("gdiplus\GdipFillPath", "ptr", g, "ptr", b, "ptr", card)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", b)
    } else
        GT_FillPath(g, card, th.fill)

    ; Concentric icon tile (radius = card radius - margin) + glyph
    ir := Max(2 * S, R - m), ix := x + m, iy := y + m
    ip := GT_RoundPath(ix, iy, isz, isz, ir)
    GT_FillPath(g, ip, GT_Lerp(GT_KINDS[kind], 0xFFFFFFFF, th.accentIcon))
    b := GT_Grad(ix, iy, isz, isz, [0x40FFFFFF, 0x00FFFFFF, 0x00FFFFFF], [0, 0.6, 1])
    DllCall("gdiplus\GdipFillPath", "ptr", g, "ptr", b, "ptr", ip)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", b)
    DllCall("gdiplus\GdipDeletePath", "ptr", ip)
    ip := GT_RoundPath(ix + 0.5, iy + 0.5, isz - 1, isz - 1, ir - 0.5)
    GT_StrokeGrad(g, ip, ix, iy, isz, isz, [0x66FFFFFF, 0x0DFFFFFF, 0x26FFFFFF], [0, 0.5, 1], 1)
    DllCall("gdiplus\GdipDeletePath", "ptr", ip)
    switch kind {
        case "warn":   GT_Exclaim(g, ix, iy, isz, 0xFFFFFFFF)
        case "info":   GT_PauseBars(g, ix, iy, isz, 0xFFFFFFFF)
        case "update": GT_DownArrow(g, ix, iy, isz, 0xFFFFFFFF)
        default:       GT_Check(g, ix, iy, isz, 0xFFFFFFFF)
    }

    ; Texts
    cy := y + h / 2, tx := x + textX, tw := w - textX - 20 * S
    GT_Text(g, title, fTitle, th.title, tx, cy - 21 * S, tw, 21 * S, fmtL)
    GT_Text(g, sub, fSub, th.sub, tx, cy, tw, 19 * S, fmtL)

    ; Specular rim + thin outline (glass), or a 1 px edge (solid)
    if glass {
        rp := GT_RoundPath(x + 0.6, y + 0.6, w - 1.2, h - 1.2, R - 0.6)
        GT_StrokeGrad(g, rp, x, y, w, h, [th.rimTop, th.rimMid, th.rimBot], [0, 0.5, 1], 1.2)
        DllCall("gdiplus\GdipDeletePath", "ptr", rp)
        op := GT_RoundPath(x - 0.5, y - 0.5, w + 1, h + 1, R + 0.5), edge := th.outline
    } else
        op := GT_RoundPath(x + 0.5, y + 0.5, w - 1, h - 1, R - 0.5), edge := th.edge
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "uint", edge, "float", 1, "int", 2, "ptr*", &pen)
    DllCall("gdiplus\GdipDrawPath", "ptr", g, "ptr", pen, "ptr", op)
    DllCall("gdiplus\GdipDeletePen", "ptr", pen)
    DllCall("gdiplus\GdipDeletePath", "ptr", op)
    DllCall("gdiplus\GdipDeletePath", "ptr", card)

    ; Window: the bitmap is sent to DWM ONCE (invisible, above the screen)
    gw := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x80000 +E0x08000000")   ; layered + no-activate
    gw.Show("NA x-32000 y-32000 w1 h1")
    GT.gui := gw, GT.hwnd := gw.Hwnd
    pt := Buffer(8), NumPut("int", GT.xHid, "int", GT.yHid, pt)
    sz := Buffer(8), NumPut("int", winW, "int", canvH, sz)
    src := Buffer(8, 0)
    DllCall("UpdateLayeredWindow", "ptr", GT.hwnd, "ptr", 0, "ptr", pt, "ptr", sz
          , "ptr", hdc, "ptr", src, "uint", 0, "uint*", 1 << 24, "uint", 2)

    ; Release EVERYTHING used for drawing: DWM already has the content
    if glass {
        DllCall("gdiplus\GdipDeleteBrush", "ptr", tex)
        DllCall("gdiplus\GdipDisposeImage", "ptr", blurred)
    }
    for f in [fTitle, fSub]
        DllCall("gdiplus\GdipDeleteFont", "ptr", f)
    for fm in [famR, famSB]
        if fm
            DllCall("gdiplus\GdipDeleteFontFamily", "ptr", fm)
    DllCall("gdiplus\GdipDeleteStringFormat", "ptr", fmtL)
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", g)
    DllCall("SelectObject", "ptr", hdc, "ptr", obm)
    DllCall("DeleteObject", "ptr", hbm)
    DllCall("DeleteDC", "ptr", hdc)
    DllCall("gdiplus\GdiplusShutdown", "ptr", tok)
}

GT_Step() {
    Critical
    global GT, GTCFG
    now := A_TickCount
    switch GT.phase {
        case "in":
            p := Min((now - GT.t0) / GTCFG.inMs, 1)
            e := GT.anim = "Slide" ? GT_EaseOutBack(p, 1.15) : GT_EaseOutCubic(p)
            x := GT.xHid + (GT.xVis - GT.xHid) * e
            y := GT.yHid + (GT.yVis - GT.yHid) * e
            a := 255 * GT_EaseOutCubic(p)
            if (p >= 1)
                GT.phase := "hold", GT.holdUntil := now + GT.holdMs
        case "hold":
            if (now >= GT.holdUntil)
                GT.phase := "out", GT.t0 := now
            return
        case "out":
            if (GT.anim = "None") {
                GT_Free()
                return
            }
            p := Min((now - GT.t0) / GTCFG.outMs, 1)
            e := GT_EaseInCubic(p)
            x := GT.xVis + (GT.xHid - GT.xVis) * e
            y := GT.yVis + (GT.yHid - GT.yVis) * e
            a := 255 * (1 - e)
            if (p >= 1) {
                GT_Free()
                return
            }
        default:
            SetTimer GT_Step, 0
            return
    }
    GT_Move(x, y, a)
}

GT_Click(wParam, lParam, msg, hwnd) {
    Critical
    global GT, GTCFG
    if (!GT.hwnd || hwnd != GT.hwnd)
        return
    now := A_TickCount
    if (GT.phase = "hold")
        GT.phase := "out", GT.t0 := now
    else if (GT.phase = "in") {
        p := Min((now - GT.t0) / GTCFG.inMs, 1)
        GT.phase := "out", GT.t0 := now - Round((1 - p) * GTCFG.outMs)
    }
}

; Removes the toast and frees the window, the timer and the 1 ms clock
GT_Free() {
    global GT
    SetTimer GT_Step, 0
    GT_HiRes(false)
    if GT.gui {
        try GT.gui.Destroy()
    }
    GT.gui := 0, GT.hwnd := 0, GT.phase := ""
}

GT_SolidLight() {                         ; light or dark solid card
    global GTCFG
    if (GTCFG.solidTheme != "")
        return GTCFG.solidTheme = "light"
    try return RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme")
    return false
}

GT_Exclaim(g, ix, iy, isz, col) {          ; "!" for warnings
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "uint", col, "float", isz * 0.11, "int", 2, "ptr*", &pen)
    DllCall("gdiplus\GdipSetPenStartCap", "ptr", pen, "int", 2)
    DllCall("gdiplus\GdipSetPenEndCap", "ptr", pen, "int", 2)
    DllCall("gdiplus\GdipDrawLine", "ptr", g, "ptr", pen
          , "float", ix + isz * 0.5, "float", iy + isz * 0.27, "float", ix + isz * 0.5, "float", iy + isz * 0.56)
    DllCall("gdiplus\GdipDeletePen", "ptr", pen)
    d := isz * 0.13, br := 0
    DllCall("gdiplus\GdipCreateSolidFill", "uint", col, "ptr*", &br)
    DllCall("gdiplus\GdipFillEllipse", "ptr", g, "ptr", br
          , "float", ix + isz * 0.5 - d / 2, "float", iy + isz * 0.70 - d / 2, "float", d, "float", d)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", br)
}

GT_DownArrow(g, ix, iy, isz, col) {        ; arrow into a tray, for updates
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "uint", col, "float", isz * 0.09, "int", 2, "ptr*", &pen)
    DllCall("gdiplus\GdipSetPenStartCap", "ptr", pen, "int", 2)
    DllCall("gdiplus\GdipSetPenEndCap", "ptr", pen, "int", 2)
    DllCall("gdiplus\GdipSetPenLineJoin", "ptr", pen, "int", 2)
    DllCall("gdiplus\GdipDrawLine", "ptr", g, "ptr", pen
          , "float", ix + isz * 0.5, "float", iy + isz * 0.25, "float", ix + isz * 0.5, "float", iy + isz * 0.58)
    pts := Buffer(24)
    NumPut("float", ix + isz * 0.36, "float", iy + isz * 0.45
         , "float", ix + isz * 0.5,  "float", iy + isz * 0.59
         , "float", ix + isz * 0.64, "float", iy + isz * 0.45, pts)
    DllCall("gdiplus\GdipDrawLines", "ptr", g, "ptr", pen, "ptr", pts, "int", 3)
    tray := Buffer(32)
    NumPut("float", ix + isz * 0.3, "float", iy + isz * 0.64
         , "float", ix + isz * 0.3, "float", iy + isz * 0.73
         , "float", ix + isz * 0.7, "float", iy + isz * 0.73
         , "float", ix + isz * 0.7, "float", iy + isz * 0.64, tray)
    DllCall("gdiplus\GdipDrawLines", "ptr", g, "ptr", pen, "ptr", tray, "int", 4)
    DllCall("gdiplus\GdipDeletePen", "ptr", pen)
}

GT_PauseBars(g, ix, iy, isz, col) {        ; "||" for paused
    bw := isz * 0.12, bh := isz * 0.40, gap := isz * 0.10
    x0 := ix + isz / 2 - gap / 2 - bw, y0 := iy + (isz - bh) / 2
    for xx in [x0, x0 + bw + gap] {
        p := GT_RoundPath(xx, y0, bw, bh, bw / 2)
        GT_FillPath(g, p, col)
        DllCall("gdiplus\GdipDeletePath", "ptr", p)
    }
}

; Screen capture + blur at 1/4 resolution + saturation; picks the theme by luminance
; (B, cardTop = position of the card inside the captured area)
GT_CaptureBlur(capX, capY, capW, capH, S, B, cardTop, ch, pw, &th) {
    global GTCFG, GT_THEMES
    hdcS := DllCall("GetDC", "ptr", 0, "ptr")
    hdcM := DllCall("CreateCompatibleDC", "ptr", hdcS, "ptr")
    hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcS, "int", capW, "int", capH, "ptr")
    ob := DllCall("SelectObject", "ptr", hdcM, "ptr", hbm, "ptr")
    DllCall("BitBlt", "ptr", hdcM, "int", 0, "int", 0, "int", capW, "int", capH
          , "ptr", hdcS, "int", capX, "int", capY, "uint", 0x00CC0020)
    DllCall("SelectObject", "ptr", hdcM, "ptr", ob)
    DllCall("DeleteDC", "ptr", hdcM)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdcS)
    srcB := 0
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "ptr", hbm, "ptr", 0, "ptr*", &srcB)
    DllCall("DeleteObject", "ptr", hbm)

    iaPlain := GT_IA(1), iaSat := GT_IA(GTCFG.saturation)

    ; 1/8 copy: used to measure luminance (and as a fallback blur)
    f := 8, sw := Max(1, capW // f), sh := Max(1, capH // f)
    small := GT_Bitmap(sw, sh), gsm := GT_BmpGraphics(small)
    GT_DrawRR(gsm, srcB, 0, 0, sw, sh, 0, 0, capW, capH, iaPlain)
    lum := GT_AvgLum(small, B // f, Max(0, cardTop // f), Min(sw - 1, (B + pw) // f), Min(sh - 1, (cardTop + ch) // f))
    th := lum > 165 ? GT_THEMES.light : GT_THEMES.dark

    ; Blur at 1/4 resolution (looks the same, ~16x fewer pixels)
    q := 4, qw := Max(1, capW // q), qh := Max(1, capH // q)
    mid := GT_Bitmap(qw, qh), gmid := GT_BmpGraphics(mid)
    GT_DrawRR(gmid, srcB, 0, 0, qw, qh, 0, 0, capW, capH, iaPlain)
    blurred := GT_Bitmap(capW, capH), gbl := GT_BmpGraphics(blurred)
    if GT_Blur(mid, GTCFG.blur * S / q)
        GT_DrawRR(gbl, mid, 0, 0, capW, capH, 0, 0, qw, qh, iaSat)
    else
        GT_DrawRR(gbl, small, 0, 0, capW, capH, 0, 0, sw, sh, iaSat)

    for ia in [iaPlain, iaSat]
        DllCall("gdiplus\GdipDisposeImageAttributes", "ptr", ia)
    for gg in [gsm, gmid, gbl]
        DllCall("gdiplus\GdipDeleteGraphics", "ptr", gg)
    for im in [small, mid, srcB]
        DllCall("gdiplus\GdipDisposeImage", "ptr", im)
    return blurred
}

GT_Blur(bmp, radius) {
    try {
        guid := Buffer(16)
        DllCall("ole32\CLSIDFromString", "wstr", "{633C80A4-1843-482b-9EF2-BE2834C5FDD4}", "ptr", guid)
        eff := 0
        if (A_PtrSize = 8)
            st := DllCall("gdiplus\GdipCreateEffect", "ptr", guid, "ptr*", &eff)
        else
            st := DllCall("gdiplus\GdipCreateEffect", "uint", NumGet(guid, 0, "uint"), "uint", NumGet(guid, 4, "uint")
                        , "uint", NumGet(guid, 8, "uint"), "uint", NumGet(guid, 12, "uint"), "ptr*", &eff)
        if (st != 0 || !eff)
            return false
        p := Buffer(8), NumPut("float", Min(radius, 255), "int", 0, p)
        DllCall("gdiplus\GdipSetEffectParameters", "ptr", eff, "ptr", p, "uint", 8)
        st := DllCall("gdiplus\GdipBitmapApplyEffect", "ptr", bmp, "ptr", eff, "ptr", 0, "int", 0, "ptr", 0, "ptr", 0)
        DllCall("gdiplus\GdipDeleteEffect", "ptr", eff)
        return st = 0
    }
    return false
}

GT_AvgLum(bmp, x0, y0, x1, y1) {
    tot := 0, n := 0, yy := y0
    while (yy <= y1) {
        xx := x0
        while (xx <= x1) {
            px := 0
            DllCall("gdiplus\GdipBitmapGetPixel", "ptr", bmp, "int", xx, "int", yy, "uint*", &px)
            tot += 0.2126 * ((px >> 16) & 0xFF) + 0.7152 * ((px >> 8) & 0xFF) + 0.0722 * (px & 0xFF)
            n++, xx++
        }
        yy++
    }
    return n ? tot / n : 0
}

GT_Shadow(g, x, y, w, h, r, S, k) {
    global GTCFG
    N := Round(GTCFG.shadowReach * S), oy := 8 * S, acc := 0
    Loop N + 1 {
        i := N - A_Index + 1
        dd := i / S
        target := (0.22 * Exp(-(dd * dd) / (2 * 13 * 13)) + 0.10 * Exp(-(dd * dd) / (2 * 3.5 * 3.5))) * k
        if (target <= acc)
            continue
        q := Round((1 - (1 - target) / (1 - acc)) * 255)
        if (q <= 0)
            continue
        p := GT_RoundPath(x - i, y - i + oy, w + 2 * i, h + 2 * i, r + i)
        GT_FillPath(g, p, q << 24)
        DllCall("gdiplus\GdipDeletePath", "ptr", p)
        acc := 1 - (1 - acc) * (1 - q / 255)
    }
}

GT_Check(g, ix, iy, isz, col) {          ; check mark drawn with a rounded stroke
    pts := Buffer(24)
    NumPut("float", ix + isz * 0.29, "float", iy + isz * 0.52
         , "float", ix + isz * 0.44, "float", iy + isz * 0.67
         , "float", ix + isz * 0.72, "float", iy + isz * 0.36, pts)
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "uint", col, "float", isz * 0.095, "int", 2, "ptr*", &pen)
    DllCall("gdiplus\GdipSetPenStartCap", "ptr", pen, "int", 2)   ; LineCapRound
    DllCall("gdiplus\GdipSetPenEndCap", "ptr", pen, "int", 2)
    DllCall("gdiplus\GdipSetPenLineJoin", "ptr", pen, "int", 2)   ; LineJoinRound
    DllCall("gdiplus\GdipDrawLines", "ptr", g, "ptr", pen, "ptr", pts, "int", 3)
    DllCall("gdiplus\GdipDeletePen", "ptr", pen)
}

GT_RoundPath(x, y, w, h, r) {
    p := 0
    DllCall("gdiplus\GdipCreatePath", "int", 0, "ptr*", &p)
    r := Max(0.5, Min(r, w / 2, h / 2)), d := r * 2
    DllCall("gdiplus\GdipAddPathArc", "ptr", p, "float", x,         "float", y,         "float", d, "float", d, "float", 180, "float", 90)
    DllCall("gdiplus\GdipAddPathArc", "ptr", p, "float", x + w - d, "float", y,         "float", d, "float", d, "float", 270, "float", 90)
    DllCall("gdiplus\GdipAddPathArc", "ptr", p, "float", x + w - d, "float", y + h - d, "float", d, "float", d, "float", 0,   "float", 90)
    DllCall("gdiplus\GdipAddPathArc", "ptr", p, "float", x,         "float", y + h - d, "float", d, "float", d, "float", 90,  "float", 90)
    DllCall("gdiplus\GdipClosePathFigure", "ptr", p)
    return p
}

GT_FillPath(g, p, argb) {
    b := 0
    DllCall("gdiplus\GdipCreateSolidFill", "uint", argb, "ptr*", &b)
    DllCall("gdiplus\GdipFillPath", "ptr", g, "ptr", b, "ptr", p)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", b)
}

GT_Grad(x, y, w, h, cols, pos) {
    rc := Buffer(16), NumPut("float", x, "float", y - 1, "float", w, "float", h + 2, rc)
    b := 0, n := cols.Length
    DllCall("gdiplus\GdipCreateLineBrushFromRect", "ptr", rc, "uint", cols[1], "uint", cols[n], "int", 1, "int", 0, "ptr*", &b)
    cb := Buffer(4 * n), pb := Buffer(4 * n)
    for i, col in cols
        NumPut("uint", col, cb, (i - 1) * 4), NumPut("float", pos[i], pb, (i - 1) * 4)
    DllCall("gdiplus\GdipSetLinePresetBlend", "ptr", b, "ptr", cb, "ptr", pb, "int", n)
    return b
}

GT_StrokeGrad(g, p, x, y, w, h, cols, pos, width) {
    b := GT_Grad(x, y, w, h, cols, pos), pen := 0
    DllCall("gdiplus\GdipCreatePen2", "ptr", b, "float", width, "int", 2, "ptr*", &pen)
    DllCall("gdiplus\GdipDrawPath", "ptr", g, "ptr", pen, "ptr", p)
    DllCall("gdiplus\GdipDeletePen", "ptr", pen)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", b)
}

GT_Text(g, str, font, argb, x, y, w, h, fmt) {
    rc := Buffer(16), NumPut("float", x, "float", y, "float", w, "float", h, rc)
    b := 0
    DllCall("gdiplus\GdipCreateSolidFill", "uint", argb, "ptr*", &b)
    DllCall("gdiplus\GdipDrawString", "ptr", g, "wstr", str, "int", -1, "ptr", font, "ptr", rc, "ptr", fmt, "ptr", b)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", b)
}

GT_MeasureW(g, str, font, fmt) {
    lay := Buffer(16), NumPut("float", 0, "float", 0, "float", 4000, "float", 400, lay)
    box := Buffer(16, 0)
    DllCall("gdiplus\GdipMeasureString", "ptr", g, "wstr", str, "int", -1, "ptr", font
          , "ptr", lay, "ptr", fmt, "ptr", box, "ptr", 0, "ptr", 0)
    return NumGet(box, 8, "float")
}

GT_Bitmap(w, h) {
    bmp := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", w, "int", h, "int", 0, "int", 0xE200B, "ptr", 0, "ptr*", &bmp)
    return bmp
}

GT_BmpGraphics(bmp) {
    g := 0
    DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", bmp, "ptr*", &g)
    DllCall("gdiplus\GdipSetInterpolationMode", "ptr", g, "int", 7)
    DllCall("gdiplus\GdipSetPixelOffsetMode", "ptr", g, "int", 2)
    return g
}

GT_DrawRR(g, img, dx, dy, dw, dh, sx, sy, sw, sh, ia) {
    DllCall("gdiplus\GdipDrawImageRectRect", "ptr", g, "ptr", img
          , "float", dx, "float", dy, "float", dw, "float", dh
          , "float", sx, "float", sy, "float", sw, "float", sh
          , "int", 2, "ptr", ia, "ptr", 0, "ptr", 0)
}

GT_IA(sat) {
    ia := 0
    DllCall("gdiplus\GdipCreateImageAttributes", "ptr*", &ia)
    DllCall("gdiplus\GdipSetImageAttributesWrapMode", "ptr", ia, "int", 3, "uint", 0, "int", 0)
    if (sat != 1) {
        lr := 0.3086, lg := 0.6094, lb := 0.0820, k := sat
        mtx := [(1 - k) * lr + k, (1 - k) * lr,     (1 - k) * lr,     0, 0
              , (1 - k) * lg,     (1 - k) * lg + k, (1 - k) * lg,     0, 0
              , (1 - k) * lb,     (1 - k) * lb,     (1 - k) * lb + k, 0, 0
              , 0, 0, 0, 1, 0
              , 0, 0, 0, 0, 1]
        cm := Buffer(100)
        for i, v in mtx
            NumPut("float", v, cm, (i - 1) * 4)
        DllCall("gdiplus\GdipSetImageAttributesColorMatrix", "ptr", ia, "int", 0, "int", 1, "ptr", cm, "ptr", 0, "int", 0)
    }
    return ia
}

GT_Lerp(c1, c2, t) {
    out := 0
    Loop 4 {
        sh := (A_Index - 1) * 8
        a := (c1 >> sh) & 0xFF, b := (c2 >> sh) & 0xFF
        out |= (Round(a + (b - a) * t) & 0xFF) << sh
    }
    return out
}

GT_Quality(g) {
    DllCall("gdiplus\GdipSetSmoothingMode", "ptr", g, "int", 4)
    DllCall("gdiplus\GdipSetPixelOffsetMode", "ptr", g, "int", 2)
    DllCall("gdiplus\GdipSetTextRenderingHint", "ptr", g, "int", 4)
}

GT_Family(name) {
    fam := 0
    if DllCall("gdiplus\GdipCreateFontFamilyFromName", "wstr", name, "ptr", 0, "ptr*", &fam) != 0
        return 0
    return fam
}

GT_Font(fam, size, style) {
    f := 0
    DllCall("gdiplus\GdipCreateFont", "ptr", fam, "float", size, "int", style, "int", 2, "ptr*", &f)
    return f
}

GT_MouseMonitor() {
    CoordMode "Mouse", "Screen"
    MouseGetPos &mx, &my
    Loop MonitorGetCount() {
        MonitorGet A_Index, &l, &t, &r, &b
        if (mx >= l && mx < r && my >= t && my < b)
            return A_Index
    }
    return MonitorGetPrimary()
}

GT_MonitorDpi(n) {
    MonitorGet n, &l, &t, &r, &b
    cx := (l + r) // 2, cy := (t + b) // 2
    hMon := DllCall("MonitorFromPoint", "int64", (cx & 0xFFFFFFFF) | (cy << 32), "uint", 2, "ptr")
    dx := 0, dy := 0
    try {
        if DllCall("shcore\GetDpiForMonitor", "ptr", hMon, "int", 0, "uint*", &dx, "uint*", &dy) = 0 && dx
            return dx
    }
    return A_ScreenDPI
}

GT_HiRes(on) {                            ; 1 ms timer resolution only while animating
    static active := false
    if (on && !active)
        DllCall("winmm\timeBeginPeriod", "uint", 1), active := true
    else if (!on && active)
        DllCall("winmm\timeEndPeriod", "uint", 1), active := false
}

GT_EaseOutCubic(p) {
    q := 1 - p
    return 1 - q * q * q
}

GT_EaseInCubic(p) {
    return p * p * p
}

GT_EaseOutBack(p, c1 := 1.3) {
    c3 := c1 + 1, q := p - 1
    return 1 + c3 * q * q * q + c1 * q * q
}
