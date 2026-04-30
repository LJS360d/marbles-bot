from __future__ import annotations

import argparse
import math
import threading
from concurrent.futures import Future, ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

# -----------------------------------------------------------------------------
# Script goal and design context
# -----------------------------------------------------------------------------
#
# This script builds `texture.webp` from one marble splash image.
# The expected input is `.rclone/marbles/<name>/standard/splash.avif`.
# Manual circle selection is the default. Auto detection remains available.
#
# Core extraction goals:
# 1) Select a circular marble region.
# 2) Remove light reflections.
# 3) Normalize illumination (reduce hard shadows / uneven lighting).
# 4) Sample dominant/base color and feature colors (quantization).
# 5) Detect feature shapes (edges + color difference + connected components).
# 6) Build a 2:1 RGBA texture atlas with two circular faces suitable for the
#    current Three.js sphere workflow.
#
# Practical constraints:
# - We only have a single view, not a full multi-view photogrammetry dataset.
# - Back hemisphere cannot be reconstructed physically, so the script mirrors
#   and attenuates front-side information for a plausible full-sphere texture.
# - The output is optimized for web delivery: compressed WEBP with alpha.
#
# Extending this script:
# - Improve reflection removal by replacing `reflection_mask` + inpaint logic.
# - Improve feature extraction by training a segmentation model.
# - Improve spherical synthesis by replacing mirror approximation with true
#   multi-view reconstruction inputs.
# -----------------------------------------------------------------------------


REPO_ROOT = Path(__file__).resolve().parent
MARBLES_ROOT = REPO_ROOT / ".rclone" / "marbles"
DEFAULT_OUTPUT_NAME = "texture.webp"
DEFAULT_OUTPUT_SIZE = 1024
DEFAULT_FEATURE_SIZE = 768
DEFAULT_WEBP_QUALITY = 90
DEFAULT_BATCH_STATE_FILE = (
    Path(__file__).resolve().parent / ".texture_ext_batch_last_marble"
)


@dataclass(frozen=True)
class MarbleStats:
    base_bgr: np.ndarray
    feature_palette_bgr: np.ndarray
    feature_weights: np.ndarray
    feature_mask: np.ndarray
    edge_mask: np.ndarray
    cleaned_bgr: np.ndarray
    variation_bgr: np.ndarray
    shininess: float
    transparency: float
    base_alpha: int


def ring_response(gray: np.ndarray, cx: float, cy: float, radius: float) -> float:
    h, w = gray.shape
    r = int(max(12, min(radius, min(h, w) * 0.49)))
    cx_i = int(round(cx))
    cy_i = int(round(cy))
    if cx_i - r < 0 or cy_i - r < 0 or cx_i + r >= w or cy_i + r >= h:
        return -1.0
    gx = cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3)
    gy = cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3)
    mag = np.sqrt(gx * gx + gy * gy)
    ring = np.zeros_like(gray, dtype=np.uint8)
    cv2.circle(ring, (cx_i, cy_i), r, 255, 3, cv2.LINE_AA)
    vals = mag[ring > 0]
    if vals.size == 0:
        return -1.0
    return float(np.mean(vals))


def detect_circle(image: np.ndarray) -> tuple[tuple[float, float], float]:
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (0, 0), 2.1)
    h, w = gray.shape
    candidates: list[tuple[float, float, float]] = []

    circles = cv2.HoughCircles(
        blur,
        cv2.HOUGH_GRADIENT,
        dp=1.2,
        minDist=min(h, w) / 3.0,
        param1=120,
        param2=35,
        minRadius=int(min(h, w) * 0.24),
        maxRadius=int(min(h, w) * 0.49),
    )
    if circles is not None and len(circles[0]) > 0:
        for c in circles[0][:8]:
            candidates.append((float(c[0]), float(c[1]), float(c[2])))

    _, binary = cv2.threshold(blur, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    num_labels, labels, stats, _ = cv2.connectedComponentsWithStats(
        binary, connectivity=8
    )
    if num_labels > 1:
        areas = stats[1:, cv2.CC_STAT_AREA]
        best = 1 + int(np.argmax(areas))
        mask = np.where(labels == best, 255, 0).astype(np.uint8)
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if contours:
            (x, y), r = cv2.minEnclosingCircle(max(contours, key=cv2.contourArea))
            candidates.append((float(x), float(y), float(r)))

    candidates.append((w * 0.5, h * 0.5, min(h, w) * 0.44))
    scored = [(ring_response(gray, cx, cy, r), cx, cy, r) for (cx, cy, r) in candidates]
    scored.sort(key=lambda item: item[0], reverse=True)
    _, cx, cy, r = scored[0]
    return (cx, cy), r


def manual_select_circle(
    image: np.ndarray,
    window_name: str,
    marble_name: str,
    keep_window_open: bool = False,
) -> tuple[tuple[float, float], float, bool]:
    h, w = image.shape[:2]
    center = [w // 2, h // 2]
    radius = int(min(h, w) * 0.34)
    drag_center = False
    drag_radius = False
    fast_mode = True
    anchor = (center[0], center[1])
    selected = {"done": False, "cancel": False, "single_face": False}

    def on_mouse(event: int, x: int, y: int, _flags: int, _userdata: object) -> None:
        nonlocal center, radius, drag_center, drag_radius, anchor
        if event == cv2.EVENT_LBUTTONDOWN:
            drag_center = True
            center = [int(np.clip(x, 0, w - 1)), int(np.clip(y, 0, h - 1))]
        elif event == cv2.EVENT_LBUTTONUP:
            drag_center = False
        elif event == cv2.EVENT_RBUTTONDOWN:
            drag_radius = True
            anchor = (center[0], center[1])
            radius = int(max(8, math.hypot(x - anchor[0], y - anchor[1])))
        elif event == cv2.EVENT_RBUTTONUP:
            drag_radius = False
        elif event == cv2.EVENT_MOUSEMOVE:
            if drag_center:
                center = [int(np.clip(x, 0, w - 1)), int(np.clip(y, 0, h - 1))]
            if drag_radius:
                radius = int(max(8, math.hypot(x - anchor[0], y - anchor[1])))

    cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)
    init_w = int(np.clip(w * 1.8, 1200, 2600))
    init_h = int(np.clip(h * 1.8, 900, 1800))
    cv2.resizeWindow(window_name, init_w, init_h)
    try:
        cv2.setWindowProperty(window_name, cv2.WND_PROP_TOPMOST, 1)
    except Exception:
        pass
    cv2.setMouseCallback(window_name, on_mouse)
    topmost_released = False

    def is_shift_toggle_key(key: int) -> bool:
        return key in {16, 65505, 65506}

    def is_up_key(key: int) -> bool:
        return key in {2490368, 65362, 82}

    def is_down_key(key: int) -> bool:
        return key in {2621440, 65364, 84}

    while True:
        frame = image.copy()
        cv2.circle(frame, tuple(center), int(radius), (0, 255, 255), 2, cv2.LINE_AA)
        cv2.circle(frame, tuple(center), 3, (0, 255, 0), -1, cv2.LINE_AA)
        cv2.putText(
            frame,
            f"Marble: {marble_name}",
            (18, 34),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.65,
            (220, 220, 255),
            2,
            cv2.LINE_AA,
        )
        cv2.putText(
            frame,
            "L-drag center | R-drag radius | WASD move center | Up/Down radius",
            (18, 62),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.65,
            (255, 255, 255),
            2,
            cv2.LINE_AA,
        )
        cv2.putText(
            frame,
            "Shift toggles x10 mode | F single-face | Enter confirm | Esc cancel",
            (18, 90),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.65,
            (255, 255, 255),
            2,
            cv2.LINE_AA,
        )
        cv2.putText(
            frame,
            f"Speed mode: {'x10' if fast_mode else 'x1'}",
            (18, 118),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.65,
            (180, 255, 180) if fast_mode else (210, 210, 210),
            2,
            cv2.LINE_AA,
        )
        cv2.putText(
            frame,
            f"Single-face mode: {'ON' if selected['single_face'] else 'OFF'}",
            (18, 146),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.65,
            (180, 255, 180) if selected["single_face"] else (210, 210, 210),
            2,
            cv2.LINE_AA,
        )
        cv2.imshow(window_name, frame)
        key = cv2.waitKeyEx(16)
        if not topmost_released:
            try:
                cv2.setWindowProperty(window_name, cv2.WND_PROP_TOPMOST, 0)
            except Exception:
                pass
            topmost_released = True
        if key < 0:
            continue
        if key in (13, 10, 32):
            selected["done"] = True
            break
        if key == 27:
            selected["cancel"] = True
            break

        if is_shift_toggle_key(key):
            fast_mode = not fast_mode
            continue
        if key in (ord("f"), ord("F")):
            selected["single_face"] = True
            continue

        step = 10 if fast_mode else 1
        if key in (ord("w"), ord("W")):
            center[1] -= step
        elif key in (ord("s"), ord("S")):
            center[1] += step
        elif key in (ord("a"), ord("A")):
            center[0] -= step
        elif key in (ord("d"), ord("D")):
            center[0] += step
        elif is_up_key(key):
            radius += step
        elif is_down_key(key):
            radius -= step

        center[0] = int(np.clip(center[0], 0, w - 1))
        center[1] = int(np.clip(center[1], 0, h - 1))
        max_r = min(center[0], center[1], w - center[0] - 1, h - center[1] - 1)
        radius = int(np.clip(radius, 8, max_r))

    if not keep_window_open:
        cv2.destroyWindow(window_name)
    if selected["cancel"] or not selected["done"]:
        raise RuntimeError("Manual selection cancelled")
    radius = int(
        min(radius, center[0], center[1], w - center[0] - 1, h - center[1] - 1)
    )
    radius = max(8, radius)
    return (float(center[0]), float(center[1])), float(radius), selected["single_face"]


def marble_name_from_image_path(image_path: Path) -> str:
    parent = image_path.parent
    if parent.name == "standard" and parent.parent != parent:
        return parent.parent.name
    return parent.name


def crop_marble(
    image: np.ndarray, center: tuple[float, float], radius: float
) -> tuple[np.ndarray, np.ndarray]:
    side = int(math.ceil(radius * 2.2))
    side = max(160, side)
    cx, cy = int(round(center[0])), int(round(center[1]))
    x0, y0 = cx - side // 2, cy - side // 2
    x1, y1 = x0 + side, y0 + side

    pad_l = max(0, -x0)
    pad_t = max(0, -y0)
    pad_r = max(0, x1 - image.shape[1])
    pad_b = max(0, y1 - image.shape[0])
    if any(v > 0 for v in (pad_l, pad_t, pad_r, pad_b)):
        image = cv2.copyMakeBorder(
            image, pad_t, pad_b, pad_l, pad_r, cv2.BORDER_REFLECT_101
        )
        x0 += pad_l
        x1 += pad_l
        y0 += pad_t
        y1 += pad_t

    crop = image[y0:y1, x0:x1].copy()
    local_r = int(round(side / 2.2))
    local_r = max(32, min(local_r, side // 2 - 2))
    mask = np.zeros((side, side), dtype=np.uint8)
    cv2.circle(mask, (side // 2, side // 2), int(local_r * 0.97), 255, -1, cv2.LINE_AA)
    return crop, mask


def reflection_mask(image: np.ndarray, mask: np.ndarray) -> np.ndarray:
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    h, s, v = cv2.split(hsv)
    del h
    v_in = v[mask > 0]
    s_in = s[mask > 0]
    if v_in.size == 0:
        return np.zeros_like(mask)
    v_hi = float(np.percentile(v_in, 98.8))
    s_lo = float(np.percentile(s_in, 35.0))
    high_v = v.astype(np.float32) >= v_hi
    low_s = s.astype(np.float32) <= (s_lo + 10.0)
    hot = np.where((mask > 0) & high_v & low_s, 255, 0).astype(np.uint8)
    hot = cv2.medianBlur(hot, 5)
    hot = cv2.morphologyEx(hot, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8), iterations=1)
    hot = cv2.dilate(hot, np.ones((3, 3), np.uint8), iterations=1)

    # Keep highlight removal conservative on highly reflective marbles.
    hot_ratio = float(np.mean(hot[mask > 0] > 0)) if np.any(mask > 0) else 0.0
    if hot_ratio > 0.14:
        stronger = np.where(
            (mask > 0) & (v >= np.percentile(v_in, 99.4)), 255, 0
        ).astype(np.uint8)
        hot = cv2.bitwise_and(hot, stronger)
    return hot


def remove_reflections(image: np.ndarray, refl_mask: np.ndarray) -> np.ndarray:
    if int(np.sum(refl_mask)) == 0:
        return image
    repaired = cv2.inpaint(image, refl_mask, 3, cv2.INPAINT_TELEA)
    # Blend instead of full replacement to avoid flattening subtle glossy gradients.
    blend = cv2.GaussianBlur((refl_mask > 0).astype(np.float32), (0, 0), 2.1)
    blend = np.clip(blend * 0.72, 0.0, 0.72)
    out = (
        image.astype(np.float32) * (1.0 - blend[:, :, None])
        + repaired.astype(np.float32) * blend[:, :, None]
    )
    return np.clip(out, 0, 255).astype(np.uint8)


def normalize_illumination(image: np.ndarray, mask: np.ndarray) -> np.ndarray:
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
    l = lab[:, :, 0].astype(np.float32)
    valid = mask > 0
    if not np.any(valid):
        return image
    illum = cv2.GaussianBlur(l, (0, 0), 17)
    mean_l = float(np.mean(l[valid]))
    l_corr = l / (illum + 1e-4) * float(np.mean(illum[valid]))
    l_corr = np.clip(l_corr * (mean_l / (np.mean(l_corr[valid]) + 1e-4)), 0, 255)
    illum_std = float(np.std(illum[valid]))
    strength = float(np.clip(0.40 + illum_std / 180.0, 0.35, 0.62))
    l_out = l * (1.0 - strength) + l_corr * strength
    lab[:, :, 0] = np.clip(l_out, 0, 255).astype(np.uint8)
    return cv2.cvtColor(lab, cv2.COLOR_LAB2BGR)


def quantize_palette(
    image: np.ndarray, mask: np.ndarray, k: int = 6
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
    pixels = np.float32(lab[mask > 0])
    if pixels.shape[0] < 200:
        fallback = np.array([[140, 140, 140], [180, 180, 180]], dtype=np.float32)
        weights = np.array([0.7, 0.3], dtype=np.float32)
        labels_map = np.zeros(mask.shape, dtype=np.int32)
        return fallback, weights, labels_map
    k_use = int(np.clip(k, 2, min(8, pixels.shape[0] // 120)))
    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 20, 0.25)
    _, labels, centers = cv2.kmeans(
        pixels, k_use, None, criteria, 4, cv2.KMEANS_PP_CENTERS
    )
    counts = np.bincount(labels.flatten(), minlength=k_use).astype(np.float32)
    weights = counts / (np.sum(counts) + 1e-8)
    order = np.argsort(weights)[::-1]
    centers = centers[order]
    weights = weights[order]
    centers_bgr = cv2.cvtColor(np.uint8(centers[None, :, :]), cv2.COLOR_LAB2BGR)[
        0
    ].astype(np.float32)
    remap = np.zeros(k_use, dtype=np.int32)
    remap[order] = np.arange(k_use, dtype=np.int32)
    labels_map = np.full(mask.shape, -1, dtype=np.int32)
    labels_map[mask > 0] = remap[labels.flatten()]
    return centers_bgr, weights, labels_map


def compute_shininess_and_transparency(
    image: np.ndarray, mask: np.ndarray, refl_mask: np.ndarray
) -> tuple[float, float, int]:
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    s = hsv[:, :, 1].astype(np.float32)[mask > 0]
    v = hsv[:, :, 2].astype(np.float32)[mask > 0]
    if s.size == 0:
        return 0.25, 0.2, 255

    refl_ratio = float(np.mean(refl_mask[mask > 0] > 0))
    low_sat = float(np.mean(s < 55))
    mean_v = float(np.mean(v) / 255.0)
    std_v = float(np.std(v) / 255.0)

    shininess = float(np.clip(refl_ratio * 3.5 + 0.08, 0.0, 1.0))
    transparency = float(
        np.clip(low_sat * 0.68 + (mean_v - 0.42) * 0.36 + std_v * 0.30, 0.0, 1.0)
    )
    if transparency < 0.30:
        alpha = 255
    elif transparency < 0.55:
        alpha = int(245 - (transparency - 0.30) * (35 / 0.25))
    else:
        alpha = int(210 - (transparency - 0.55) * (60 / 0.45))
    alpha = int(np.clip(alpha, 140, 255))
    return shininess, transparency, alpha


def build_feature_mask(
    image: np.ndarray,
    mask: np.ndarray,
    base_bgr: np.ndarray,
    edge_mask: np.ndarray,
    labels_map: np.ndarray,
) -> np.ndarray:
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB).astype(np.float32)
    base_lab = cv2.cvtColor(
        np.uint8(np.clip(base_bgr, 0, 255))[None, None, :], cv2.COLOR_BGR2LAB
    ).astype(np.float32)[0, 0, :]
    d = np.sqrt(np.sum((lab - base_lab[None, None, :]) ** 2, axis=2))
    valid_d = d[mask > 0]
    if valid_d.size == 0:
        return np.zeros_like(mask, dtype=np.uint8)
    thr = float(np.percentile(valid_d, 74))
    color_feat = np.where((mask > 0) & (d >= thr), 255, 0).astype(np.uint8)
    # Quantized cluster regions improve coherent "same-color area" encapsulation.
    region_feat = np.where((mask > 0) & (labels_map > 0), 255, 0).astype(np.uint8)
    region_feat = cv2.morphologyEx(
        region_feat, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8), iterations=1
    )
    edge_feat = cv2.dilate(edge_mask, np.ones((3, 3), np.uint8), iterations=1)
    feature = cv2.bitwise_or(region_feat, color_feat)
    feature = cv2.bitwise_or(feature, edge_feat)
    feature = cv2.bitwise_and(feature, mask)
    feature = cv2.medianBlur(feature, 5)
    feature = cv2.morphologyEx(
        feature, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8), iterations=1
    )

    n, labels, stats, _ = cv2.connectedComponentsWithStats(feature, connectivity=8)
    clean = np.zeros_like(feature)
    if n <= 1:
        return clean
    min_area = max(36, int(np.sum(mask > 0) * 0.0008))
    for i in range(1, n):
        if int(stats[i, cv2.CC_STAT_AREA]) >= min_area:
            clean[labels == i] = 255
    return clean


def marble_analysis(crop: np.ndarray, mask: np.ndarray) -> MarbleStats:
    refl = reflection_mask(crop, mask)
    refl_removed = remove_reflections(crop, refl)
    clean = normalize_illumination(refl_removed, mask)

    palette, weights, labels_map = quantize_palette(clean, mask, k=7)
    base = palette[0].astype(np.float32)

    shininess, transparency, alpha = compute_shininess_and_transparency(
        clean, mask, refl
    )
    base = np.clip(base * (1.0 + 0.18 * shininess) + 14.0 * shininess, 0, 255)

    gray = cv2.cvtColor(clean, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 42, 118)
    edges = np.where((mask > 0) & (edges > 0), 255, 0).astype(np.uint8)

    features = build_feature_mask(clean, mask, base, edges, labels_map)
    variation = cv2.GaussianBlur(clean, (0, 0), 12.0)
    return MarbleStats(
        base_bgr=base,
        feature_palette_bgr=palette,
        feature_weights=weights,
        feature_mask=features,
        edge_mask=edges,
        cleaned_bgr=clean,
        variation_bgr=variation,
        shininess=shininess,
        transparency=transparency,
        base_alpha=alpha,
    )


def remap_disk_source(
    src: np.ndarray, out_w: int, out_h: int
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    h, w = src.shape[:2]
    cy = (h - 1) * 0.5
    cx = (w - 1) * 0.5
    r = min(cx, cy) * 0.97

    y, x = np.mgrid[0:out_h, 0:out_w].astype(np.float32)
    u = (x + 0.5) / out_w
    v = (y + 0.5) / out_h

    lon = (u - 0.5) * math.tau
    lat = (0.5 - v) * math.pi
    xs = np.sin(lon) * np.cos(lat)
    ys = np.sin(lat)
    zs = np.cos(lon) * np.cos(lat)

    x_proj = np.where(zs >= 0.0, xs, -xs)
    y_proj = ys
    map_x = (cx + x_proj * r).astype(np.float32)
    map_y = (cy - y_proj * r).astype(np.float32)
    z_front = np.clip(zs * 0.5 + 0.5, 0.0, 1.0).astype(np.float32)
    return map_x, map_y, z_front


def enforce_wrap_horizontal(rgba: np.ndarray) -> np.ndarray:
    out = rgba.copy()
    h, w = out.shape[:2]
    if w < 4:
        return out
    avg = (
        (out[:, 0, :].astype(np.uint16) + out[:, w - 1, :].astype(np.uint16)) // 2
    ).astype(np.uint8)
    out[:, 0, :] = avg
    out[:, w - 1, :] = avg
    band = max(3, w // 256)
    for i in range(1, band + 1):
        a = i / (band + 1)
        out[:, i, :] = cv2.addWeighted(out[:, i, :], 1.0 - a, avg, a, 0)
        out[:, w - 1 - i, :] = cv2.addWeighted(out[:, w - 1 - i, :], 1.0 - a, avg, a, 0)
    if h > 8:
        out[:2, :, :] = out[2:4, :, :]
        out[h - 2 :, :, :] = out[h - 4 : h - 2, :, :]
    return out


def apply_circular_alpha_mask(
    rgba: np.ndarray, single_face_features: bool
) -> np.ndarray:
    out = rgba.copy()
    h, w = out.shape[:2]
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    cy = (h - 1) * 0.5
    r = (h - 1) * 0.5 + 0.5

    if single_face_features:
        centers = [(w - 1) * 0.25, (w - 1) * 0.75]
        inside = np.zeros((h, w), dtype=bool)
        for cx in centers:
            dx = x - cx
            dy = y - cy
            inside |= (dx * dx + dy * dy) <= (r * r)
    else:
        cx = (w - 1) * 0.5
        dx = x - cx
        dy = y - cy
        inside = (dx * dx + dy * dy) <= (r * r)

    out[:, :, 3] = np.where(inside, 255, 0).astype(np.uint8)
    out[:, :, :3] = np.where(out[:, :, 3:4] > 0, out[:, :, :3], 0)
    return out


def ensure_two_to_one_rgba(rgba: np.ndarray) -> np.ndarray:
    h, w = rgba.shape[:2]
    target_w = h * 2
    if w == target_w:
        return rgba
    if w < target_w:
        out = np.zeros((h, target_w, 4), dtype=np.uint8)
        x0 = (target_w - w) // 2
        out[:, x0 : x0 + w, :] = rgba
        return out
    return cv2.resize(rgba, (target_w, h), interpolation=cv2.INTER_AREA)


def synthesize_texture(
    stats: MarbleStats, out_size: int, single_face_features: bool
) -> np.ndarray:
    out_h = out_size
    out_w = out_size * 2
    side = out_size
    clean_sq = cv2.resize(
        stats.cleaned_bgr, (side, side), interpolation=cv2.INTER_CUBIC
    ).astype(np.float32)
    var_sq = cv2.resize(
        stats.variation_bgr, (side, side), interpolation=cv2.INTER_CUBIC
    ).astype(np.float32)
    feat_sq = (
        cv2.resize(
            stats.feature_mask, (side, side), interpolation=cv2.INTER_LINEAR
        ).astype(np.float32)
        / 255.0
    )
    edge_sq = (
        cv2.resize(
            stats.edge_mask, (side, side), interpolation=cv2.INTER_LINEAR
        ).astype(np.float32)
        / 255.0
    )

    base_sq = np.tile(stats.base_bgr[None, None, :], (side, side, 1)).astype(np.float32)
    base_mix = np.clip(0.70 + 0.15 * stats.shininess, 0.60, 0.90)
    body_sq = base_sq * base_mix + var_sq * (1.0 - base_mix)
    feature_w_sq = np.clip(feat_sq * 0.78, 0.0, 0.9)
    edge_w_sq = np.clip(edge_sq * 0.30, 0.0, 0.38)

    front_tex = (
        body_sq * (1.0 - feature_w_sq[:, :, None]) + clean_sq * feature_w_sq[:, :, None]
    )
    front_tex = front_tex + (clean_sq - body_sq) * edge_w_sq[:, :, None] * 0.55
    front_tex = np.clip(front_tex, 0, 255).astype(np.uint8)

    if single_face_features:
        back_tex = np.tile(stats.base_bgr[None, None, :], (side, side, 1))
        back_tex = np.clip(back_tex, 0, 255).astype(np.uint8)
    else:
        back_tex = cv2.flip(front_tex, 1)

    front_alpha = np.full((side, side), stats.base_alpha, dtype=np.uint8)
    if stats.transparency > 0.25:
        front_alpha = np.clip(
            front_alpha.astype(np.float32)
            + (cv2.cvtColor(front_tex, cv2.COLOR_BGR2GRAY).astype(np.float32) / 255.0)
            * (255 - stats.base_alpha)
            * 0.18,
            0,
            255,
        ).astype(np.uint8)
    back_alpha = (
        np.full((side, side), stats.base_alpha, dtype=np.uint8)
        if single_face_features
        else front_alpha.copy()
    )

    atlas = np.zeros((out_h, out_w, 4), dtype=np.uint8)
    y, x = np.mgrid[0:out_h, 0:out_w].astype(np.float32)
    cy = (out_h - 1) * 0.5
    r = (side - 1) * 0.5 + 0.5
    centers = [(out_w - 1) * 0.25, (out_w - 1) * 0.75]

    def stamp_disk(src_rgb: np.ndarray, src_a: np.ndarray, cx: float) -> None:
        dx = x - cx
        dy = y - cy
        inside = (dx * dx + dy * dy) <= (r * r)
        src_c = (side - 1) * 0.5
        src_r = max(8.0, (side / 2.2) * 0.97)
        src_fill_r = max(6.0, src_r - 1.5)
        scale = src_r / max(r, 1e-6)
        src_dx = dx * scale
        src_dy = dy * scale
        src_dist = np.sqrt(src_dx * src_dx + src_dy * src_dy)
        clamp_factor = np.where(
            src_dist > src_fill_r,
            src_fill_r / np.maximum(src_dist, 1e-6),
            1.0,
        ).astype(np.float32)
        src_dx = src_dx * clamp_factor
        src_dy = src_dy * clamp_factor
        map_x = np.clip(src_c + src_dx, 0, side - 1).astype(np.float32)
        map_y = np.clip(src_c + src_dy, 0, side - 1).astype(np.float32)
        sampled_rgb = cv2.remap(
            src_rgb,
            map_x,
            map_y,
            interpolation=cv2.INTER_CUBIC,
            borderMode=cv2.BORDER_REPLICATE,
        )
        sampled_a = cv2.remap(
            src_a,
            map_x,
            map_y,
            interpolation=cv2.INTER_LINEAR,
            borderMode=cv2.BORDER_REPLICATE,
        )
        atlas[inside, :3] = sampled_rgb[inside]
        atlas[inside, 3] = sampled_a[inside]

    stamp_disk(front_tex, front_alpha, centers[0])
    stamp_disk(back_tex, back_alpha, centers[1])
    return apply_circular_alpha_mask(atlas, single_face_features=True)


def process_image(
    image_path: Path,
    manual: bool,
    output_name: str,
    out_size: int,
    feature_size: int,
    quality: int,
    single_face_features: bool,
    manual_window_name: str | None = None,
    keep_manual_window_open: bool = False,
) -> bool:
    image = cv2.imread(str(image_path), cv2.IMREAD_COLOR)
    if image is None:
        return False

    manual_circle: tuple[tuple[float, float], float] | None = None
    manual_single_face = False
    if manual:
        marble_name = marble_name_from_image_path(image_path)
        window_name = (
            manual_window_name
            if manual_window_name is not None
            else f"Select marble: {marble_name}"
        )
        manual_center, manual_radius, manual_single_face = manual_select_circle(
            image,
            window_name,
            marble_name,
            keep_window_open=keep_manual_window_open,
        )
        manual_circle = (manual_center, manual_radius)
    center, radius = (
        manual_circle if manual_circle is not None else detect_circle(image)
    )
    single_face_features = single_face_features or manual_single_face

    return process_image_from_circle(
        image_path=image_path,
        center=center,
        radius=radius,
        output_name=output_name,
        out_size=out_size,
        feature_size=feature_size,
        quality=quality,
        single_face_features=single_face_features,
    )


def process_image_from_circle(
    image_path: Path,
    center: tuple[float, float],
    radius: float,
    output_name: str,
    out_size: int,
    feature_size: int,
    quality: int,
    single_face_features: bool,
) -> bool:
    image = cv2.imread(str(image_path), cv2.IMREAD_COLOR)
    if image is None:
        return False

    crop, mask = crop_marble(image, center, radius)
    crop = cv2.resize(crop, (feature_size, feature_size), interpolation=cv2.INTER_CUBIC)
    mask = cv2.resize(
        mask, (feature_size, feature_size), interpolation=cv2.INTER_NEAREST
    )
    stats = marble_analysis(crop, mask)
    texture = synthesize_texture(stats, out_size, single_face_features)
    texture = ensure_two_to_one_rgba(texture)
    out_path = image_path.parent / output_name

    try:
        Image.fromarray(cv2.cvtColor(texture, cv2.COLOR_BGRA2RGBA)).save(
            str(out_path),
            format="WEBP",
            quality=int(np.clip(quality, 65, 100)),
            method=6,
        )
        return True
    except Exception:
        return bool(
            cv2.imwrite(
                str(out_path),
                texture,
                [cv2.IMWRITE_WEBP_QUALITY, int(np.clip(quality, 65, 100))],
            )
        )


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description=(
            "Generate marble texture.webp assets from splash images. "
            "Manual circle selection is enabled by default."
        )
    )
    p.add_argument(
        "--manual",
        dest="manual",
        action="store_true",
        default=True,
        help="Use GUI circle selection (default).",
    )
    p.add_argument(
        "--auto",
        dest="manual",
        action="store_false",
        help="Use auto circle detection instead of GUI selection.",
    )
    p.add_argument(
        "--marble",
        type=str,
        default="",
        help="Process one marble from .rclone/marbles/<name>/standard/splash.avif",
    )
    p.add_argument(
        "--input",
        type=str,
        default="",
        help="Direct path to one input image (AVIF expected).",
    )
    p.add_argument("--output-name", type=str, default=DEFAULT_OUTPUT_NAME)
    p.add_argument("--output-size", type=int, default=DEFAULT_OUTPUT_SIZE)
    p.add_argument("--feature-size", type=int, default=DEFAULT_FEATURE_SIZE)
    p.add_argument("--quality", type=int, default=DEFAULT_WEBP_QUALITY)
    p.add_argument(
        "--single-face",
        dest="single_face_features",
        action="store_true",
        default=False,
        help=(
            "Front-only feature mode: back face uses mostly base color while "
            "front keeps extracted feature detail."
        ),
    )
    p.add_argument(
        "--full-sphere",
        dest="single_face_features",
        action="store_false",
        help="Mirror full feature detail between front and back faces (default).",
    )
    p.add_argument(
        "--batch-manual",
        action="store_true",
        help=(
            "Process all marble folders sequentially with manual GUI selection "
            "and persisted resume state."
        ),
    )
    p.add_argument(
        "--state-file",
        type=str,
        default=str(DEFAULT_BATCH_STATE_FILE),
        help="Resume state file used with --batch-manual.",
    )
    p.add_argument(
        "--from-start",
        action="store_true",
        help="Ignore saved state and restart from first marble in --batch-manual.",
    )
    return p.parse_args()


def gather_inputs(args: argparse.Namespace) -> list[Path]:
    if args.input:
        return [Path(args.input).expanduser().resolve()]
    if args.marble:
        return [MARBLES_ROOT / args.marble / "standard" / "splash.avif"]
    return sorted(MARBLES_ROOT.glob("*/standard/splash.avif"))


def list_marble_dirs(root: Path) -> list[Path]:
    return sorted(
        (path for path in root.iterdir() if path.is_dir()), key=lambda p: p.name
    )


def read_last_processed(state_file: Path) -> str:
    if not state_file.exists():
        return ""
    try:
        return state_file.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def write_last_processed(state_file: Path, marble_name: str) -> None:
    state_file.parent.mkdir(parents=True, exist_ok=True)
    state_file.write_text(marble_name, encoding="utf-8")


def resolve_start_index(
    marbles: list[Path], last_processed: str, from_start: bool
) -> int:
    if from_start or not last_processed:
        return 0
    names = [marble.name for marble in marbles]
    if last_processed not in names:
        return 0
    return names.index(last_processed) + 1


def run_batch_manual(args: argparse.Namespace) -> None:
    state_file = Path(args.state_file).expanduser().resolve()
    marbles = list_marble_dirs(MARBLES_ROOT)
    if not marbles:
        print(f"No marble folders found under {MARBLES_ROOT}")
        return

    start_index = resolve_start_index(
        marbles=marbles,
        last_processed=read_last_processed(state_file),
        from_start=args.from_start,
    )
    if start_index >= len(marbles):
        print("All marble folders already processed according to state file.")
        return

    done = 0
    fail = 0
    total = len(marbles) - start_index
    window_name = "Marble manual selector"
    lock = threading.Lock()
    pending: list[Future[bool]] = []

    def record_result(
        marble_name: str,
        output_path: Path,
        image_path: Path,
        ok: bool,
        error: str | None = None,
    ) -> None:
        nonlocal done, fail
        with lock:
            write_last_processed(state_file, marble_name)
            if ok:
                done += 1
                print(f"[ok] {output_path}")
            else:
                fail += 1
                if error:
                    print(f"[fail] {image_path} ({error})")
                else:
                    print(f"[fail] {image_path}")

    def attach_result_handler(
        future: Future[bool], marble_name: str, output_path: Path, image_path: Path
    ) -> None:
        def _on_done(done_future: Future[bool]) -> None:
            try:
                ok = bool(done_future.result())
                record_result(
                    marble_name=marble_name,
                    output_path=output_path,
                    image_path=image_path,
                    ok=ok,
                )
            except Exception as exc:
                record_result(
                    marble_name=marble_name,
                    output_path=output_path,
                    image_path=image_path,
                    ok=False,
                    error=str(exc),
                )

        future.add_done_callback(_on_done)

    try:
        with ThreadPoolExecutor(max_workers=1) as executor:
            for idx, marble_dir in enumerate(marbles[start_index:], start=1):
                image_path = marble_dir / "standard" / "splash.avif"
                output_path = marble_dir / args.output_name
                print(f"[{idx}/{total}] {marble_dir.name}")

                image = cv2.imread(str(image_path), cv2.IMREAD_COLOR)
                if image is None:
                    record_result(
                        marble_name=marble_dir.name,
                        output_path=output_path,
                        image_path=image_path,
                        ok=False,
                    )
                    continue

                try:
                    center, radius, manual_single_face = manual_select_circle(
                        image=image,
                        window_name=window_name,
                        marble_name=marble_dir.name,
                        keep_window_open=True,
                    )
                except RuntimeError as exc:
                    if "Manual selection cancelled" in str(exc):
                        print(
                            "Manual selection cancelled. Stopping without advancing progress."
                        )
                        break
                    record_result(
                        marble_name=marble_dir.name,
                        output_path=output_path,
                        image_path=image_path,
                        ok=False,
                        error=str(exc),
                    )
                    continue
                except KeyboardInterrupt:
                    print("\nInterrupted. Progress saved up to previous marble.")
                    break

                future = executor.submit(
                    process_image_from_circle,
                    image_path=image_path,
                    center=center,
                    radius=radius,
                    output_name=args.output_name,
                    out_size=max(256, int(args.output_size)),
                    feature_size=max(256, int(args.feature_size)),
                    quality=int(args.quality),
                    single_face_features=args.single_face_features
                    or manual_single_face,
                )
                pending.append(future)
                attach_result_handler(
                    future=future,
                    marble_name=marble_dir.name,
                    output_path=output_path,
                    image_path=image_path,
                )

            for future in pending:
                future.result()
    finally:
        try:
            cv2.destroyWindow(window_name)
        except Exception:
            pass
    print(f"Processed {done} textures, {fail} failures.")


def main() -> None:
    args = parse_args()
    if args.batch_manual:
        run_batch_manual(args)
        return
    inputs = gather_inputs(args)
    if not inputs:
        print("No input images found.")
        return

    done = 0
    fail = 0
    for image_path in inputs:
        ok = process_image(
            image_path=image_path,
            manual=args.manual,
            output_name=args.output_name,
            out_size=max(256, int(args.output_size)),
            feature_size=max(256, int(args.feature_size)),
            quality=int(args.quality),
            single_face_features=args.single_face_features,
        )
        if ok:
            done += 1
            print(f"[ok] {image_path.parent / args.output_name}")
        else:
            fail += 1
            print(f"[fail] {image_path}")
    print(f"Processed {done} textures, {fail} failures.")


if __name__ == "__main__":
    main()
