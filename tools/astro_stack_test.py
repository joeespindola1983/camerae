#!/usr/bin/env python3
"""
Pipeline completo de astrofotografia: alinhamento + stacking + denoise.

Implementa duas estrategias de alinhamento:
  1. ECC (Enhanced Correlation Coefficient) — multi-resolucao, bom para
     campos estelares com pouco movimento entre frames
  2. Star-based — detecta estrelas, casa pontos brilhantes entre frames,
     calcula transformacao affine

Stacking:
  - Mean: media aritmetica pixel a pixel (melhor SNR, requer mais frames)
  - Median: mediana pixel a pixel (remove avioes/satelites/outliers)

Denoise:
  - fastNlMeansDenoisingColored pos-stack com h configuravel

Uso:
    python3 astro_stack_test.py /caminho/dos/frames
    python3 astro_stack_test.py /caminho/dos/frames --method ecc --count 15 --stack mean
    python3 astro_stack_test.py /caminho/dos/frames --method stars --count 10 --denoise 7
"""

import argparse
import os
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

import cv2
import numpy as np


# ---------------------------------------------------------------------------
# Parametros de alinhamento (afetam qualidade e velocidade)
# ---------------------------------------------------------------------------

@dataclass
class AlignConfig:
    max_dimension: int = 1920          # Reduz imagens para este tamanho maximo
    ecc_iterations: int = 200          # Max iteracoes ECC por nivel
    ecc_epsilon: float = 1e-6          # Tolerancia de convergencia ECC
    ecc_pyramid_levels: int = 4        # Niveis da piramide multi-resolucao
    star_threshold: float = 0.75       # Percentil de luminancia para detectar estrelas
    star_min_distance: int = 8         # Distancia minima entre estrelas (px)
    star_max_count: int = 200          # Max estrelas a usar para matching
    ransac_threshold: float = 3.0      # Threshold RANSAC (px) para matching estelar
    ransac_confidence: float = 0.99    # Confianca RANSAC


# ---------------------------------------------------------------------------
# Star detection
# ---------------------------------------------------------------------------

def detect_stars(
    gray: np.ndarray,
    threshold_percentile: float = 0.75,
    min_distance: int = 8,
    max_count: int = 200,
) -> list[tuple[float, float, float]]:
    """
    Detecta estrelas em imagem grayscale.

    Retorna lista de (x, y, brightness) ordenada por brilho decrescente.
    """
    h, w = gray.shape[:2]

    # Encontrar pixels acima do percentil
    threshold = np.percentile(gray, threshold_percentile * 100)
    bright = gray > threshold

    # Usar connected components para agrupar pixels brilhantes vizinhos
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    dilated = cv2.dilate(bright.astype(np.uint8), kernel, iterations=1)

    num_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(
        dilated, connectivity=8
    )

    stars = []
    for i in range(1, num_labels):
        area = stats[i, cv2.CC_STAT_AREA]
        if area < 2 or area > 80:  # Filtrar pixels isolados e regioes grandes
            continue

        cx = centroids[i, 0]
        cy = centroids[i, 1]
        # Brilho medio na regiao
        mask = (labels == i)
        brightness = np.mean(gray[mask])

        stars.append((cx, cy, brightness))

    # Ordenar por brilho e limitar
    stars.sort(key=lambda s: s[2], reverse=True)
    stars = stars[:max_count]

    # Filtrar estrelas muito proximas (non-maximum suppression simples)
    filtered = []
    for star in stars:
        too_close = False
        for kept in filtered:
            dist = np.sqrt((star[0] - kept[0]) ** 2 + (star[1] - kept[1]) ** 2)
            if dist < min_distance:
                too_close = True
                break
        if not too_close:
            filtered.append(star)

    return filtered


def draw_stars(image: np.ndarray, stars: list, color=(0, 255, 0)) -> np.ndarray:
    """Desenha estrelas detectadas na imagem para visualizacao."""
    out = image.copy()
    for x, y, b in stars:
        radius = max(2, int(b / 50))
        cv2.circle(out, (int(x), int(y)), radius, color, 1)
    return out


# ---------------------------------------------------------------------------
# Alinhamento ECC (Enhanced Correlation Coefficient)
# ---------------------------------------------------------------------------

def align_ecc_multiscale(
    reference_gray: np.ndarray,
    target_gray: np.ndarray,
    config: AlignConfig,
) -> np.ndarray | None:
    """
    Alinha target ao reference usando ECC multi-resolucao.

    Retorna a matriz de warp 2x3 (affine) ou None se falhar.
    """
    warp_matrix = np.eye(2, 3, dtype=np.float32)

    for level in range(config.ecc_pyramid_levels, 0, -1):
        scale = 1.0 / (2 ** (level - 1))
        ref_scaled = cv2.resize(reference_gray, None, fx=scale, fy=scale,
                                interpolation=cv2.INTER_AREA)
        tgt_scaled = cv2.resize(target_gray, None, fx=scale, fy=scale,
                                interpolation=cv2.INTER_AREA)

        # Ajustar warp para a escala atual
        level_warp = warp_matrix.copy()
        level_warp[0, 2] *= scale
        level_warp[1, 2] *= scale

        criteria = (cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT,
                    config.ecc_iterations, config.ecc_epsilon)

        try:
            # Usar MOTION_AFFINE para permitir rotacao + translacao + escala
            _, level_warp = cv2.findTransformECC(
                ref_scaled, tgt_scaled, level_warp,
                cv2.MOTION_AFFINE, criteria,
                None,  # inputMask
                5,     # gaussFiltSize (pode ser necessario ajustar)
            )
        except cv2.error:
            # ECC pode falhar se imagens sao muito diferentes
            # Tentar com MOTION_TRANSLATION como fallback
            try:
                simple_warp = np.eye(2, 3, dtype=np.float32)
                simple_warp[0, 2] = level_warp[0, 2]
                simple_warp[1, 2] = level_warp[1, 2]
                _, level_warp = cv2.findTransformECC(
                    ref_scaled, tgt_scaled, simple_warp,
                    cv2.MOTION_TRANSLATION, criteria,
                )
            except cv2.error:
                continue

        # Restaurar escala da translacao
        level_warp[0, 2] /= scale
        level_warp[1, 2] /= scale
        warp_matrix = level_warp

    return warp_matrix


# ---------------------------------------------------------------------------
# Alinhamento por deteccao de estrelas
# ---------------------------------------------------------------------------

def align_stars_ransac(
    reference_gray: np.ndarray,
    target_gray: np.ndarray,
    config: AlignConfig,
) -> np.ndarray | None:
    """
    Detecta estrelas em ambas as imagens, casa por similaridade espacial,
    e estima transformacao affine via RANSAC.
    """
    # Detectar estrelas
    ref_stars = detect_stars(reference_gray, config.star_threshold,
                             config.star_min_distance, config.star_max_count)
    tgt_stars = detect_stars(target_gray, config.star_threshold,
                             config.star_min_distance, config.star_max_count)

    if len(ref_stars) < 8 or len(tgt_stars) < 8:
        return None  # Estrelas insuficientes

    # Extrair coordenadas
    ref_pts = np.float32([(s[0], s[1]) for s in ref_stars])
    tgt_pts = np.float32([(s[0], s[1]) for s in tgt_stars])

    # Criar descritores simples para matching: posicao relativa ao centro
    h, w = reference_gray.shape[:2]
    ref_center = np.array([w / 2, h / 2])
    tgt_center = np.array([w / 2, h / 2])

    # Para cada estrela de referencia, encontrar a melhor correspondencia
    # Baseado em similaridade de padrao local (patch matching simples)
    matches = []
    patch_size = 21
    half = patch_size // 2

    for i, (rx, ry, _) in enumerate(ref_stars[:min(len(ref_stars), 100)]):
        # Extrair patch ao redor da estrela de referencia
        rxi, ryi = int(rx), int(ry)
        if (rxi - half < 0 or rxi + half >= w or
                ryi - half < 0 or ryi + half >= h):
            continue

        ref_patch = reference_gray[ryi - half:ryi + half + 1,
                                   rxi - half:rxi + half + 1]

        best_corr = -1
        best_j = -1

        for j, (tx, ty, _) in enumerate(tgt_stars[:min(len(tgt_stars), 100)]):
            txi, tyi = int(tx), int(ty)
            if (txi - half < 0 or txi + half >= w or
                    tyi - half < 0 or tyi + half >= h):
                continue

            tgt_patch = target_gray[tyi - half:tyi + half + 1,
                                    txi - half:txi + half + 1]

            # Normalized cross-correlation
            corr = cv2.matchTemplate(ref_patch, tgt_patch, cv2.TM_CCOEFF_NORMED)[0, 0]
            if corr > best_corr:
                best_corr = corr
                best_j = j

        if best_corr > 0.3 and best_j >= 0:
            matches.append((i, best_j, best_corr))

    if len(matches) < 6:
        return None

    # Construir pares de pontos com os matches
    src_pts = np.float32([ref_pts[m[0]] for m in matches]).reshape(-1, 1, 2)
    dst_pts = np.float32([tgt_pts[m[1]] for m in matches]).reshape(-1, 1, 2)

    # Estimar transformacao affine via RANSAC
    affine, inliers = cv2.estimateAffinePartial2D(
        src_pts, dst_pts,
        method=cv2.RANSAC,
        ransacReprojThreshold=config.ransac_threshold,
        confidence=config.ransac_confidence,
    )

    if affine is None:
        return None

    return affine


# ---------------------------------------------------------------------------
# Alinhamento hibrido: stars primeiro, ECC refina
# ---------------------------------------------------------------------------

def align_hybrid(
    reference_gray: np.ndarray,
    target_gray: np.ndarray,
    config: AlignConfig,
) -> np.ndarray | None:
    """
    Alinhamento hibrido: star-based para estimativa inicial, ECC para refinar.
    """
    # Primeiro: star-based
    affine = align_stars_ransac(reference_gray, target_gray, config)
    if affine is None:
        # Fallback: ECC puro
        return align_ecc_multiscale(reference_gray, target_gray, config)

    # Refinar com ECC (single-level, partindo do affine das estrelas)
    criteria = (cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT,
                100, config.ecc_epsilon)

    try:
        _, refined = cv2.findTransformECC(
            reference_gray, target_gray, affine,
            cv2.MOTION_AFFINE, criteria,
        )
        return refined
    except cv2.error:
        return affine  # Retorna affine das estrelas se ECC falhar


# ---------------------------------------------------------------------------
# Pre-processamento
# ---------------------------------------------------------------------------

def preprocess_for_alignment(
    image: np.ndarray,
    max_dimension: int,
) -> np.ndarray:
    """Prepara imagem grayscale para alinhamento."""
    if max_dimension > 0:
        h, w = image.shape[:2]
        if max(h, w) > max_dimension:
            scale = max_dimension / max(h, w)
            image = cv2.resize(image, None, fx=scale, fy=scale,
                               interpolation=cv2.INTER_AREA)

    # CLAHE para melhorar contraste local (ajuda ECC e deteccao de estrelas)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    return clahe.apply(image)


# ---------------------------------------------------------------------------
# Stacking
# ---------------------------------------------------------------------------

def warp_image(image: np.ndarray, warp_matrix: np.ndarray,
               output_size: tuple[int, int]) -> np.ndarray:
    """Aplica warp affine na imagem."""
    return cv2.warpAffine(
        image, warp_matrix, output_size,
        flags=cv2.INTER_LANCZOS4 + cv2.WARP_INVERSE_MAP,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=0,
    )


def mean_stack(images: list[np.ndarray]) -> np.ndarray:
    """Stack por media aritmetica."""
    stacked = np.mean(images, axis=0)
    return np.clip(stacked, 0, 255).astype(np.uint8)


def median_stack(images: list[np.ndarray]) -> np.ndarray:
    """Stack por mediana (remove outliers como avioes/satelites)."""
    stacked = np.median(images, axis=0)
    return np.clip(stacked, 0, 255).astype(np.uint8)


def sigma_clip_stack(images: list[np.ndarray],
                     sigma: float = 2.0,
                     iterations: int = 2) -> np.ndarray:
    """
    Stack com sigma clipping: rejeita pixels que desviam mais de N sigmas
    da media. Otimo para remover trails de satelite e raios cosmicos.
    """
    stack = np.array(images, dtype=np.float32)
    mask = np.ones(stack.shape[0], dtype=bool)

    for _ in range(iterations):
        mean = np.mean(stack[mask], axis=0)
        std = np.std(stack[mask], axis=0)
        std = np.maximum(std, 1.0)  # Evitar divisao por zero

        new_mask = np.ones(len(images), dtype=bool)
        for i in range(len(images)):
            diff = np.abs(stack[i] - mean)
            if np.any(diff > sigma * std):
                new_mask[i] = False

        if np.array_equal(mask, new_mask):
            break
        mask = new_mask

    result = np.mean(stack[mask], axis=0)
    return np.clip(result, 0, 255).astype(np.uint8)


# ---------------------------------------------------------------------------
# Post-processamento
# ---------------------------------------------------------------------------

# -- Gamma correction ---------------------------------------------------------

def apply_gamma(image: np.ndarray, gamma: float = 1.0) -> np.ndarray:
    """
    Correcao gamma em float32 para evitar posterizacao (banding).
    gamma < 1.0 → clareia  |  gamma > 1.0 → escurece  |  gamma = 1.0 → neutro
    """
    if abs(gamma - 1.0) < 0.001:
        return image

    # Trabalhar em float32 [0, 1] para preservar gradientes suaves
    is_uint8 = image.dtype == np.uint8
    img_f = image.astype(np.float32) / 255.0 if is_uint8 else image.astype(np.float32)
    img_f = np.power(np.maximum(img_f, 0.0), gamma)

    if is_uint8:
        return np.clip(img_f * 255.0, 0, 255).astype(np.uint8)
    return img_f


# -- CLAHE (Contrast Limited Adaptive Histogram Equalization) -----------------

def apply_clahe(
    image: np.ndarray,
    clip_limit: float = 2.0,
    tile_size: int = 8,
) -> np.ndarray:
    """
    Contraste local adaptativo — realca nebulosidade e detalhes fracos
    sem criar halos artificiais.

    clip_limit: quanto maior, mais contraste (1.5 leve, 3.0 medio, 6.0 forte)
    tile_size: tamanho da grade (8 = default, 16 = areas maiores)
    """
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)

    clahe = cv2.createCLAHE(clipLimit=clip_limit, tileGridSize=(tile_size, tile_size))
    l_eq = clahe.apply(l)

    lab_eq = cv2.merge([l_eq, a, b])
    return cv2.cvtColor(lab_eq, cv2.COLOR_LAB2BGR)


# -- Saturation / Vibrance ----------------------------------------------------

def apply_saturation(
    image: np.ndarray,
    saturation_scale: float = 1.0,
    vibrance: bool = True,
) -> np.ndarray:
    """
    Ajusta saturacao das cores.
    saturation_scale: 1.0 = neutro, 1.15 = leve, 1.30 = medio, 1.50 = forte
    vibrance: True = prioriza cores menos saturadas (mais natural)
    """
    if abs(saturation_scale - 1.0) < 0.001:
        return image

    # Trabalhar em float32 [0, 1]
    is_uint8 = image.dtype == np.uint8
    img_f = image.astype(np.float32) / 255.0 if is_uint8 else image.astype(np.float32)
    hsv = cv2.cvtColor(img_f, cv2.COLOR_BGR2HSV)
    h, s, v = cv2.split(hsv)

    if vibrance:
        # Vibrance: escala inversamente proporcional a saturacao atual
        weights = 1.0 - s  # s ja esta em [0, 1]
        scale = 1.0 + (saturation_scale - 1.0) * weights
        s = s * scale
    else:
        s = s * saturation_scale

    s = np.clip(s, 0, 1)
    hsv = cv2.merge([h, s, v])
    result = cv2.cvtColor(hsv, cv2.COLOR_HSV2BGR)

    if is_uint8:
        return np.clip(result * 255.0, 0, 255).astype(np.uint8)
    return result


# -- Curves / Levels (S-curve para contraste) ---------------------------------

def apply_s_curve(
    image: np.ndarray,
    shadow_boost: float = 0.0,
    highlight_dampen: float = 0.0,
    midtone_contrast: float = 1.0,
) -> np.ndarray:
    """
    Curva tonal em S trabalhando em float32 para evitar banding.

    shadow_boost:    0.0 a 0.15 — clareia sombras (cuidado com ruido)
    highlight_dampen: 0.0 a 0.20 — comprime altas luzes (preserva nucleos de estrelas)
    midtone_contrast: 1.0 a 1.40 — contraste nos tons medios
    """
    if (abs(shadow_boost) < 0.001 and abs(highlight_dampen) < 0.001
            and abs(midtone_contrast - 1.0) < 0.001):
        return image

    # Converter para float32 [0, 1]
    is_uint8 = image.dtype == np.uint8
    if is_uint8:
        y = image.astype(np.float32) / 255.0
    else:
        y = image if image.dtype == np.float32 else image.astype(np.float32)

    # Midtone contrast: multiplica distancia do cinza medio (0.5)
    if abs(midtone_contrast - 1.0) > 0.001:
        y = 0.5 + (y - 0.5) * midtone_contrast

    # Shadow boost (levanta a parte baixa da curva com transicao suave)
    if shadow_boost > 0.001:
        shadow_lift = shadow_boost * np.square(1.0 - y)
        y = y + shadow_lift

    # Highlight dampening (comprime a parte alta suavemente)
    if highlight_dampen > 0.001:
        highlight_squash = highlight_dampen * np.square(y)
        y = y - highlight_squash

    y = np.clip(y, 0, 1)

    if is_uint8:
        return (y * 255.0).astype(np.uint8)
    return y


# -- Light pollution / Background gradient removal ----------------------------

def remove_background_gradient(
    image: np.ndarray,
    filter_size: int = 64,
    subtraction_strength: float = 0.85,
) -> np.ndarray:
    """
    Remove gradiente de fundo (poluicao luminosa) usando morphological opening.
    Funciona bem para vinhetas e gradientes suaves de cidade.

    filter_size: tamanho do elemento estruturante (32-128, maior = remove
                 gradientes mais suaves). Deve ser maior que as estrelas.
    subtraction_strength: 0.5 a 1.0 — o quanto subtrair do background estimado
    """
    if filter_size < 3:
        return image

    # Estimar background com morphological opening
    kernel = cv2.getStructuringElement(
        cv2.MORPH_ELLIPSE, (filter_size, filter_size),
    )

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    background = cv2.morphologyEx(gray, cv2.MORPH_OPEN, kernel)

    # Suavizar o background estimado
    background = cv2.GaussianBlur(background, (filter_size | 1, filter_size | 1), 0)

    # Subtrair de cada canal
    result = image.astype(np.float32)
    bg = background.astype(np.float32)
    mean_bg = np.mean(bg)

    for c in range(3):
        result[:, :, c] = result[:, :, c] - (bg - mean_bg) * subtraction_strength

    return np.clip(result, 0, 255).astype(np.uint8)


# -- Star mask + morphological star reduction ---------------------------------

def create_star_mask(
    image: np.ndarray,
    threshold_percentile: float = 95.0,
    min_radius: int = 1,
    max_radius: int = 8,
) -> np.ndarray:
    """
    Cria mascara binaria das estrelas para processamento seletivo.

    Retorna mask 0-1 float32 onde 1 = estrela.
    """
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    threshold = np.percentile(gray, threshold_percentile)

    _, mask = cv2.threshold(gray, threshold, 255, cv2.THRESH_BINARY)

    # Dilatar para capturar todo o disco da estrela
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    mask = cv2.dilate(mask, kernel, iterations=2)

    return mask.astype(np.float32) / 255.0


def reduce_stars(
    image: np.ndarray,
    mask: np.ndarray | None = None,
    erosion_strength: float = 0.5,
    threshold_percentile: float = 95.0,
) -> np.ndarray:
    """
    Reduz o tamanho das estrelas via erosao morfologica na star mask.
    Deixa as estrelas mais finas/tight, destacando nebulosidade.

    erosion_strength: 0.0 (sem efeito) a 1.0 (reducao maxima)
    """
    if erosion_strength < 0.01:
        return image

    if mask is None:
        mask = create_star_mask(image, threshold_percentile)

    kernel_size = max(1, int(erosion_strength * 5))
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel_size, kernel_size))

    eroded = cv2.erode(image, kernel, iterations=1)

    # Blend: usar eroded apenas onde tem estrelas
    mask_3ch = np.stack([mask] * 3, axis=-1)
    result = image.astype(np.float32) * (1 - mask_3ch) + eroded.astype(np.float32) * mask_3ch

    return np.clip(result, 0, 255).astype(np.uint8)


# -- Unsharp mask (nitidez controlada) ----------------------------------------

def apply_unsharp_mask(
    image: np.ndarray,
    amount: float = 1.0,
    radius: float = 2.0,
    threshold: float = 0.0,
) -> np.ndarray:
    """
    Nitidez via unsharp mask — mais controle que um kernel fixo.

    amount:    intensidade (0.5 leve, 1.0 medio, 2.0 forte)
    radius:    raio do blur gaussiano em px (1.5-3.0 tipico)
    threshold: minima diferenca para aplicar nitidez (0 = tudo, 3 = so bordas fortes)
    """
    if amount < 0.01:
        return image

    blurred = cv2.GaussianBlur(image, (0, 0), radius)
    sharpened = cv2.addWeighted(image, 1.0 + amount, blurred, -amount, 0)

    if threshold > 0:
        diff = cv2.absdiff(image, sharpened)
        diff_gray = cv2.cvtColor(diff, cv2.COLOR_BGR2GRAY)
        _, mask = cv2.threshold(diff_gray, threshold, 255, cv2.THRESH_BINARY)
        mask_3ch = np.stack([mask] * 3, axis=-1).astype(np.float32) / 255.0
        sharpened = image.astype(np.float32) * (1 - mask_3ch) + sharpened.astype(np.float32) * mask_3ch

    return np.clip(sharpened, 0, 255).astype(np.uint8)


# -- Auto-exposure compensation ------------------------------------------------

def auto_exposure(image: np.ndarray, target_mean: float = 0.30) -> np.ndarray:
    """
    Ajusta exposicao automaticamente baseado na luminancia media.
    target_mean: luminancia alvo (0.30 = tipico para astro)
    """
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY).astype(np.float32) / 255.0
    current_mean = float(np.mean(gray))

    if current_mean < 0.001:
        return image

    # Calcular fator de correcao
    correction = target_mean / current_mean
    # Limitar para evitar estouro
    correction = max(0.7, min(2.0, correction))

    result = image.astype(np.float32) * correction
    return np.clip(result, 0, 255).astype(np.uint8)


# -- Pipeline completo ---------------------------------------------------------

@dataclass
class PostProcessConfig:
    """Configuracao de pos-processamento."""
    # Denoise
    denoise_h: float = 7.0
    denoise_hColor: float | None = None

    # Gamma
    gamma: float = 0.0  # 0 = off, < 1 clareia

    # CLAHE
    clahe_clip: float = 0.0  # 0 = off
    clahe_tile: int = 8

    # Saturacao
    saturation: float = 0.0  # 0 = off, 1.0 = neutro (nao aplica)

    # Curves
    s_curve_shadow: float = 0.0
    s_curve_highlight: float = 0.0
    s_curve_contrast: float = 1.0

    # Background removal
    bg_filter_size: int = 0  # 0 = off

    # Star reduction
    star_erosion: float = 0.0  # 0 = off

    # Unsharp mask
    unsharp_amount: float = 0.0  # 0 = off
    unsharp_radius: float = 2.0

    # Auto exposure
    auto_exposure_target: float = 0.0  # 0 = off


PRESET_POSTPROCESS = {
    "natural": PostProcessConfig(
        # Ultra-leve: so realca um pouco sem perder qualidade
        denoise_h=3.0,
        gamma=0.90,
        saturation=1.06,
        s_curve_contrast=1.04,
        unsharp_amount=0.4,
        unsharp_radius=1.5,
    ),
    "light": PostProcessConfig(
        denoise_h=5.0,
        gamma=0.85,
        saturation=1.08,
        s_curve_contrast=1.06,
        unsharp_amount=0.5,
        unsharp_radius=1.8,
    ),
    "balanced": PostProcessConfig(
        denoise_h=7.0,
        gamma=0.80,
        clahe_clip=1.2,
        clahe_tile=8,
        saturation=1.12,
        s_curve_shadow=0.03,
        s_curve_contrast=1.08,
        unsharp_amount=0.7,
        unsharp_radius=2.0,
    ),
    "strong": PostProcessConfig(
        denoise_h=10.0,
        gamma=0.72,
        clahe_clip=2.0,
        clahe_tile=8,
        saturation=1.20,
        s_curve_shadow=0.06,
        s_curve_highlight=0.03,
        s_curve_contrast=1.12,
        bg_filter_size=64,
        unsharp_amount=1.0,
        unsharp_radius=2.5,
    ),
}


def post_process(
    image: np.ndarray,
    config: PostProcessConfig | None = None,
    denoise_h: float = 7.0,
    denoise_hColor: float | None = None,
    sharpen: bool = True,
) -> np.ndarray:
    """
    Pipeline completo de pos-processamento astrofotografico.

    Ordem:
      1. Background extraction (remove gradiente)
      2. Auto-exposure (corrige exposicao)
      3. Star mask + reduction
      4. Gamma (clareia)
      5. CLAHE (contraste local)
      6. S-curve (contraste tonal)
      7. Saturation (cores)
      8. Unsharp mask (nitidez)
      9. Denoise (reducao de ruido)

    Pode receber um PostProcessConfig completo ou usar os parametros simples
    de compatibilidade (denoise_h, sharpen).
    """
    if config is None:
        config = PostProcessConfig(
            denoise_h=denoise_h,
            denoise_hColor=denoise_hColor,
            unsharp_amount=1.0 if sharpen else 0.0,
        )

    if config.denoise_hColor is None:
        config.denoise_hColor = config.denoise_h

    result = image.copy()

    # 1. Background extraction
    if config.bg_filter_size > 0:
        result = remove_background_gradient(result, config.bg_filter_size)

    # 2. Auto-exposure
    if config.auto_exposure_target > 0:
        result = auto_exposure(result, config.auto_exposure_target)

    # 3. Star reduction
    if config.star_erosion > 0.01:
        result = reduce_stars(result, erosion_strength=config.star_erosion)

    # 4. Gamma
    if config.gamma > 0.01:
        result = apply_gamma(result, config.gamma)

    # 5. CLAHE
    if config.clahe_clip > 0.01:
        result = apply_clahe(result, config.clahe_clip, config.clahe_tile)

    # 6. S-curve
    if (config.s_curve_shadow > 0.001 or config.s_curve_highlight > 0.001
            or abs(config.s_curve_contrast - 1.0) > 0.001):
        result = apply_s_curve(
            result,
            config.s_curve_shadow,
            config.s_curve_highlight,
            config.s_curve_contrast,
        )

    # 7. Saturation
    if config.saturation > 0.01 and abs(config.saturation - 1.0) > 0.001:
        result = apply_saturation(result, config.saturation)

    # 8. Unsharp mask
    if config.unsharp_amount > 0.01:
        result = apply_unsharp_mask(
            result, config.unsharp_amount, config.unsharp_radius,
        )

    # 9. Denoise (por ultimo para limpar ruido introduzido pelo stretching)
    if config.denoise_h > 0:
        result = cv2.fastNlMeansDenoisingColored(
            result, None, config.denoise_h, config.denoise_hColor, 7, 21,
        )

    return result


# ---------------------------------------------------------------------------
# Visualizacao
# ---------------------------------------------------------------------------

def add_label(img: np.ndarray, text: str, position: tuple = (0, 0)) -> np.ndarray:
    """Adiciona label com fundo semi-transparente."""
    out = img.copy()
    font = cv2.FONT_HERSHEY_SIMPLEX
    font_scale = 0.8
    thickness = 2
    color = (255, 255, 255)
    bg = (0, 0, 0)

    lines = text.split("\n")
    x, y = position if position != (0, 0) else (12, 30)

    for i, line in enumerate(lines):
        py = y + i * 32
        (tw, th), _ = cv2.getTextSize(line, font, font_scale, thickness)
        cv2.rectangle(out, (x, py - th - 4), (x + tw + 10, py + 6), bg, -1)
        cv2.putText(out, line, (x + 4, py), font, font_scale, color, thickness)

    return out


def build_comparison(
    original: np.ndarray,
    aligned_stack: np.ndarray,
    denoised: np.ndarray,
    frame_count: int,
    denoise_h: float,
) -> np.ndarray:
    """Monta comparacao: Original | Stack | Denoised (linha unica)."""
    h, w = original.shape[:2]
    display_max = 700
    if max(h, w) > display_max:
        scale = display_max / max(h, w)
        new_w = int(w * scale)
        new_h = int(h * scale)
    else:
        new_w, new_h = w, h

    def resize(img):
        if img.shape[:2] != (new_h, new_w):
            return cv2.resize(img, (new_w, new_h), interpolation=cv2.INTER_AREA)
        return img

    orig = resize(original)
    stack = resize(aligned_stack)
    den = resize(denoised)

    panels = [
        add_label(orig, "Original (1 frame)"),
        add_label(stack, f"Stack ({frame_count} frames)\nAlinhado + Mean"),
        add_label(den, f"Denoise h={denoise_h}"),
    ]

    return np.hstack(panels)


# ---------------------------------------------------------------------------
# Pipeline principal
# ---------------------------------------------------------------------------

@dataclass
class StackingResult:
    stacked: np.ndarray
    processed: np.ndarray       # Apos post-processamento completo
    denoised: np.ndarray         # Compatibilidade: = processed
    frame_count: int
    aligned_count: int
    failed_count: int
    elapsed: float
    warp_matrices: list[np.ndarray | None] = field(default_factory=list)


def run_pipeline(
    frame_paths: list[Path],
    config: AlignConfig,
    alignment_method: str = "hybrid",
    stack_method: str = "mean",
    denoise_h: float = 7.0,
    progress: bool = True,
    post_config: PostProcessConfig | None = None,
) -> StackingResult:
    """
    Pipeline completo: load → align → stack → denoise.
    """
    t0 = time.perf_counter()

    if len(frame_paths) < 2:
        raise ValueError("Precisa de pelo menos 2 frames")

    # Carregar e converter para grayscale
    color_frames = []
    gray_frames = []

    reference_color = cv2.imread(str(frame_paths[0]), cv2.IMREAD_COLOR)
    if reference_color is None:
        raise ValueError(f"Nao foi possivel ler: {frame_paths[0]}")

    reference_gray = cv2.cvtColor(reference_color, cv2.COLOR_BGR2GRAY)
    reference_gray = preprocess_for_alignment(reference_gray, config.max_dimension)

    if config.max_dimension > 0:
        h, w = reference_color.shape[:2]
        if max(h, w) > config.max_dimension:
            scale = config.max_dimension / max(h, w)
            new_w = int(w * scale)
            new_h = int(h * scale)
            reference_color = cv2.resize(reference_color, (new_w, new_h),
                                         interpolation=cv2.INTER_AREA)

    color_frames.append(reference_color)
    gray_frames.append(reference_gray)

    # Alinhar frames subsequentes
    warp_matrices: list[np.ndarray | None] = [np.eye(2, 3, dtype=np.float32)]
    aligned_count = 1
    failed_count = 0

    for i, path in enumerate(frame_paths[1:], start=1):
        color = cv2.imread(str(path), cv2.IMREAD_COLOR)
        if color is None:
            failed_count += 1
            warp_matrices.append(None)
            continue

        gray = cv2.cvtColor(color, cv2.COLOR_BGR2GRAY)
        gray_processed = preprocess_for_alignment(gray, config.max_dimension)

        # Alinhar ao reference (primeiro frame)
        if alignment_method == "ecc":
            warp = align_ecc_multiscale(reference_gray, gray_processed, config)
        elif alignment_method == "stars":
            warp = align_stars_ransac(reference_gray, gray_processed, config)
            # Inverter warp porque queremos target → reference
            if warp is not None:
                warp = cv2.invertAffineTransform(warp)
        elif alignment_method == "hybrid":
            warp = align_hybrid(reference_gray, gray_processed, config)
            # Inverter warp (stars retorna reference → target, queremos target → reference)
            if warp is not None:
                warp = cv2.invertAffineTransform(warp)
        else:
            raise ValueError(f"Metodo desconhecido: {alignment_method}")

        if warp is not None:
            # Redimensionar color para o mesmo tamanho do reference se necessario
            if config.max_dimension > 0:
                h, w = color.shape[:2]
                if max(h, w) > config.max_dimension:
                    scale = config.max_dimension / max(h, w)
                    new_w = int(w * scale)
                    new_h = int(h * scale)
                    color = cv2.resize(color, (new_w, new_h),
                                       interpolation=cv2.INTER_AREA)

            # Aplicar warp
            h, w = reference_color.shape[:2]
            aligned = warp_image(color, warp, (w, h))
            color_frames.append(aligned)
            gray_frames.append(gray_processed)  # Para referencia apenas
            warp_matrices.append(warp)
            aligned_count += 1
        else:
            failed_count += 1
            warp_matrices.append(None)

        if progress:
            print(f"\r  Alinhando: {i + 1}/{len(frame_paths)} "
                  f"(ok={aligned_count}, fail={failed_count})", end="", flush=True)

    if progress:
        print()

    if aligned_count < 2:
        raise RuntimeError(f"Apenas {aligned_count} frames alinhados, "
                           f"precisa de pelo menos 2")

    # Stacking
    if progress:
        print(f"  Stacking: {stack_method} com {aligned_count} frames...")

    if stack_method == "mean":
        stacked = mean_stack(color_frames)
    elif stack_method == "median":
        stacked = median_stack(color_frames)
    elif stack_method == "sigma_clip":
        stacked = sigma_clip_stack(color_frames)
    else:
        raise ValueError(f"Stack method desconhecido: {stack_method}")

    # Post-processamento
    if progress:
        print(f"  Post-processando...")

    processed = post_process(stacked, config=post_config)
    denoised = processed  # compatibilidade

    elapsed = time.perf_counter() - t0

    return StackingResult(
        stacked=stacked,
        processed=processed,
        denoised=denoised,
        frame_count=len(frame_paths),
        aligned_count=aligned_count,
        failed_count=failed_count,
        elapsed=elapsed,
        warp_matrices=warp_matrices,
    )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def find_frames(directory: Path, count: int | None = None) -> list[Path]:
    """Encontra frames JPG no diretorio, ordenados."""
    jpgs = sorted(
        p for p in directory.iterdir()
        if p.suffix.lower() in (".jpg", ".jpeg")
    )
    if count:
        jpgs = jpgs[:count]
    return jpgs


def main():
    parser = argparse.ArgumentParser(
        description="Pipeline astro: alinhamento + stacking + pos-processamento",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Exemplos:
  %(prog)s ~/frames
      Stack com metodo hibrido, mean stack, pos-processamento balanced

  %(prog)s ~/frames --count 15 --method ecc --stack median --preset strong
      Stack de 15 frames com ECC, mediana, processamento forte

  %(prog)s ~/frames --count 10 --method stars --denoise 5 --gamma 0.75 --saturation 1.15
      Stack com parametros manuais de gamma e saturacao

  %(prog)s ~/frames --count 5 --quick
      Stack rapido sem denoise, util para testar alinhamento

Presets de pos-processamento:
  natural  = gamma 0.90, saturacao 1.06, contraste 1.04, unsharp 0.4, denoise h=3
  light    = gamma 0.85, saturacao 1.08, contraste 1.06, unsharp 0.5, denoise h=5
  balanced = gamma 0.80, clahe 1.2, saturacao 1.12, contraste 1.08, shadow 0.03, unsharp 0.7, denoise h=7
  strong   = gamma 0.72, clahe 2.0, saturacao 1.20, contraste 1.12, bg filter 64, unsharp 1.0, denoise h=10
        """,
    )
    # -- Input / output
    parser.add_argument("directory", type=str,
                        help="Diretorio com frames JPG do timelapse")
    parser.add_argument("--output", "-o", type=str, default=None,
                        help="Diretorio de saida (default: <dir>/_astro_stack)")
    parser.add_argument("--max-dimension", type=int, default=1920,
                        help="Dimensao maxima (default: 1920)")

    # -- Stacking
    parser.add_argument("--count", "-c", type=int, default=20,
                        help="Numero de frames para stack (default: 20)")
    parser.add_argument("--method", "-m",
                        choices=["hybrid", "ecc", "stars"],
                        default="hybrid",
                        help="Metodo de alinhamento (default: hybrid)")
    parser.add_argument("--stack", "-s",
                        choices=["mean", "median", "sigma_clip"],
                        default="mean",
                        help="Metodo de stacking (default: mean)")
    parser.add_argument("--star-threshold", type=float, default=0.75,
                        help="Percentil para deteccao de estrelas (default: 0.75)")

    # -- Post-processamento: preset (conveniencia)
    parser.add_argument("--preset", "-p",
                        choices=["natural", "light", "balanced", "strong", "none"],
                        default="natural",
                        help="Preset de pos-processamento (default: natural)")
    parser.add_argument("--quick", action="store_true",
                        help="Modo rapido: 5 frames, ECC, sem denoise")

    # -- Post-processamento: denoise
    parser.add_argument("--denoise", "-d", type=float, default=None,
                        help="Forca do denoise h (sobrescreve o preset)")
    parser.add_argument("--no-denoise", action="store_true",
                        help="Desliga o denoise")

    # -- Post-processamento: gamma
    parser.add_argument("--gamma", type=float, default=None,
                        help="Gamma (< 1 clareia, > 1 escurece. Ex: 0.72)")

    # -- Post-processamento: CLAHE
    parser.add_argument("--clahe", type=float, default=None,
                        help="CLAHE clip limit (1.5 leve, 3.0 medio, 6.0 forte)")
    parser.add_argument("--clahe-tile", type=int, default=8,
                        help="CLAHE tile size (default: 8)")

    # -- Post-processamento: saturacao
    parser.add_argument("--saturation", type=float, default=None,
                        help="Escala de saturacao (1.0 neutro, 1.2 medio, 1.4 forte)")

    # -- Post-processamento: S-curve
    parser.add_argument("--s-curve-shadow", type=float, default=None,
                        help="S-curve shadow boost (0.0 a 0.15)")
    parser.add_argument("--s-curve-highlight", type=float, default=None,
                        help="S-curve highlight dampen (0.0 a 0.20)")
    parser.add_argument("--s-curve-contrast", type=float, default=None,
                        help="S-curve midtone contrast (1.0 a 1.40)")

    # -- Post-processamento: background removal
    parser.add_argument("--bg-filter", type=int, default=None,
                        help="Tamanho do filtro de background (32-128, 0=off)")

    # -- Post-processamento: star reduction
    parser.add_argument("--star-erosion", type=float, default=None,
                        help="Reducao de estrelas (0.0 a 1.0)")

    # -- Post-processamento: unsharp mask
    parser.add_argument("--unsharp", type=float, default=None,
                        help="Unsharp mask amount (0.5 leve, 1.0 medio, 2.0 forte)")
    parser.add_argument("--unsharp-radius", type=float, default=2.0,
                        help="Unsharp mask radius (default: 2.0)")

    # -- Post-processamento: auto-exposure
    parser.add_argument("--auto-exposure", type=float, default=None,
                        help="Auto-exposure target mean (0.25-0.35, 0=off)")

    args = parser.parse_args()

    # -- Construir PostProcessConfig ------------------------------------------
    if args.preset != "none" and args.preset in PRESET_POSTPROCESS:
        pp = PRESET_POSTPROCESS[args.preset]
    else:
        pp = PostProcessConfig()

    # Sobrescrever com valores explicitos da CLI
    if args.no_denoise:
        pp.denoise_h = 0.0
    if args.denoise is not None:
        pp.denoise_h = args.denoise
    if args.gamma is not None:
        pp.gamma = args.gamma
    if args.clahe is not None:
        pp.clahe_clip = args.clahe
    pp.clahe_tile = args.clahe_tile
    if args.saturation is not None:
        pp.saturation = args.saturation
    if args.s_curve_shadow is not None:
        pp.s_curve_shadow = args.s_curve_shadow
    if args.s_curve_highlight is not None:
        pp.s_curve_highlight = args.s_curve_highlight
    if args.s_curve_contrast is not None:
        pp.s_curve_contrast = args.s_curve_contrast
    if args.bg_filter is not None:
        pp.bg_filter_size = args.bg_filter
    if args.star_erosion is not None:
        pp.star_erosion = args.star_erosion
    if args.unsharp is not None:
        pp.unsharp_amount = args.unsharp
    pp.unsharp_radius = args.unsharp_radius
    if args.auto_exposure is not None:
        pp.auto_exposure_target = args.auto_exposure

    if args.quick:
        args.count = 5
        args.method = "hybrid"
        args.stack = "mean"
        pp = PostProcessConfig()  # Tudo desligado

    denoise_h = pp.denoise_h

    # Validar
    directory = Path(args.directory).expanduser().resolve()
    if not directory.is_dir():
        print(f"ERRO: Diretorio nao encontrado: {directory}", file=sys.stderr)
        sys.exit(1)

    frames = find_frames(directory, args.count)
    if len(frames) < 2:
        print(f"ERRO: Apenas {len(frames)} frames encontrados (min: 2)", file=sys.stderr)
        sys.exit(1)

    print(f"Frames encontrados: {len(frames)}")
    print(f"  Primeiro: {frames[0].name}")
    print(f"  Ultimo:   {frames[-1].name}")
    print(f"  Metodo:   {args.method}")
    print(f"  Stack:    {args.stack}")
    print(f"  Dimensao: {args.max_dimension}px")
    print(f"\n  Pos-processamento ({args.preset}):")
    print(f"    Denoise:        h={pp.denoise_h}" + (" (off)" if pp.denoise_h == 0 else ""))
    print(f"    Gamma:          {pp.gamma}" + (" (off)" if pp.gamma < 0.01 else ""))
    print(f"    CLAHE:          {pp.clahe_clip}" + (" (off)" if pp.clahe_clip < 0.01 else ""))
    print(f"    Saturation:     {pp.saturation}" + (" (off)" if pp.saturation < 0.01 else ""))
    print(f"    S-curve shadow: {pp.s_curve_shadow}" + (" (off)" if pp.s_curve_shadow < 0.01 else ""))
    print(f"    S-curve highlt: {pp.s_curve_highlight}" + (" (off)" if pp.s_curve_highlight < 0.01 else ""))
    print(f"    S-curve contr.: {pp.s_curve_contrast}" + (" (off)" if abs(pp.s_curve_contrast - 1.0) < 0.01 else ""))
    print(f"    BG filter:      {pp.bg_filter_size}" + (" (off)" if pp.bg_filter_size == 0 else ""))
    print(f"    Star erosion:   {pp.star_erosion}" + (" (off)" if pp.star_erosion < 0.01 else ""))
    print(f"    Unsharp:        {pp.unsharp_amount}" + (" (off)" if pp.unsharp_amount < 0.01 else ""))
    print(f"    Auto-exposure:  {pp.auto_exposure_target}" + (" (off)" if pp.auto_exposure_target < 0.01 else ""))
    print()

    # Config
    config = AlignConfig(
        max_dimension=args.max_dimension,
        star_threshold=args.star_threshold,
    )

    # Pipeline
    try:
        result = run_pipeline(
            frames, config,
            alignment_method=args.method,
            stack_method=args.stack,
            denoise_h=denoise_h,
            progress=True,
            post_config=pp,
        )
    except (ValueError, RuntimeError) as e:
        print(f"\nERRO: {e}", file=sys.stderr)
        sys.exit(1)

    # Output
    if args.output:
        output_dir = Path(args.output).expanduser().resolve()
    else:
        output_dir = directory / "_astro_stack"
    output_dir.mkdir(parents=True, exist_ok=True)

    # Salvar resultados
    base_name = frames[0].stem

    preset_tag = args.preset if args.preset != "none" else "custom"
    stack_path = output_dir / f"stack_{args.method}_{args.stack}_{result.aligned_count}frames_{base_name}.jpg"
    cv2.imwrite(str(stack_path), result.stacked, [cv2.IMWRITE_JPEG_QUALITY, 95])

    processed_path = output_dir / f"processed_{args.method}_{args.stack}_{result.aligned_count}frames_{preset_tag}_{base_name}.jpg"
    cv2.imwrite(str(processed_path), result.processed, [cv2.IMWRITE_JPEG_QUALITY, 95])

    denoise_suffix = f"_h{int(pp.denoise_h)}" if pp.denoise_h > 0 else ""
    denoise_path = output_dir / f"denoised_{args.method}_{args.stack}_{result.aligned_count}frames{denoise_suffix}_{base_name}.jpg"
    cv2.imwrite(str(denoise_path), result.processed, [cv2.IMWRITE_JPEG_QUALITY, 95])

    # Carregar primeiro frame original para comparacao
    first_color = cv2.imread(str(frames[0]), cv2.IMREAD_COLOR)
    if config.max_dimension > 0:
        h, w = first_color.shape[:2]
        if max(h, w) > config.max_dimension:
            scale = config.max_dimension / max(h, w)
            first_color = cv2.resize(first_color,
                                     (int(w * scale), int(h * scale)),
                                     interpolation=cv2.INTER_AREA)

    comparison = build_comparison(
        first_color, result.stacked, result.processed,
        result.aligned_count, pp.denoise_h,
    )
    comp_path = output_dir / f"comparison_{args.method}_{args.stack}_{result.aligned_count}frames_{base_name}.jpg"
    cv2.imwrite(str(comp_path), comparison, [cv2.IMWRITE_JPEG_QUALITY, 92])

    # Relatorio
    print(f"\n{'='*60}")
    print(f"RESULTADO")
    print(f"{'='*60}")
    print(f"  Frames processados:    {result.frame_count}")
    print(f"  Alinhados com sucesso: {result.aligned_count}")
    print(f"  Falhas de alinhamento: {result.failed_count}")
    print(f"  Metodo alinhamento:    {args.method}")
    print(f"  Metodo stacking:       {args.stack}")
    print(f"  Preset processamento:  {args.preset}")
    print(f"  Tempo total:           {result.elapsed:.1f}s")
    print(f"  Tempo por frame:       {result.elapsed / result.frame_count:.1f}s")
    print(f"\n  Stack:       {stack_path}")
    print(f"  Processado:  {processed_path}")
    print(f"  Comparacao:  {comp_path}")


if __name__ == "__main__":
    main()
