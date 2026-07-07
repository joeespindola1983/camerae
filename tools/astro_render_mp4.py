#!/usr/bin/env python3
"""
Renderiza um timelapse astro completo: agrupa frames → alinha → stack →
pos-processa → gera MP4 de alta qualidade via ffmpeg.

Cada grupo de N frames gera 1 frame processado no video final.

Requer ffmpeg no PATH para a etapa de encode.

Uso:
    python3 astro_render_mp4.py /caminho/dos/frames
    python3 astro_render_mp4.py /caminho/dos/frames --stack-size 10 --preset natural --fps 24
    python3 astro_render_mp4.py /caminho/dos/frames --stack-size 15 --preset balanced --fps 30 --max-dim 3840
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path

import cv2
import numpy as np


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

@dataclass
class AlignConfig:
    max_dimension: int = 0          # 0 = sem reducao (full resolution)
    ecc_iterations: int = 200
    ecc_epsilon: float = 1e-6
    ecc_pyramid_levels: int = 4


@dataclass
class PostProcessConfig:
    denoise_h: float = 3.0
    denoise_hColor: float | None = None
    gamma: float = 0.0
    clahe_clip: float = 0.0
    clahe_tile: int = 8
    saturation: float = 0.0
    s_curve_shadow: float = 0.0
    s_curve_highlight: float = 0.0
    s_curve_contrast: float = 1.0
    bg_filter_size: int = 0
    unsharp_amount: float = 0.0
    unsharp_radius: float = 2.0


PRESETS = {
    "natural": PostProcessConfig(
        denoise_h=3.0, gamma=0.90, saturation=1.06,
        s_curve_contrast=1.04, unsharp_amount=0.4, unsharp_radius=1.5,
    ),
    "light": PostProcessConfig(
        denoise_h=5.0, gamma=0.85, saturation=1.08,
        s_curve_contrast=1.06, unsharp_amount=0.5, unsharp_radius=1.8,
    ),
    "balanced": PostProcessConfig(
        denoise_h=7.0, gamma=0.80, clahe_clip=1.2, clahe_tile=8,
        saturation=1.12, s_curve_shadow=0.03, s_curve_contrast=1.08,
        unsharp_amount=0.7, unsharp_radius=2.0,
    ),
    "strong": PostProcessConfig(
        denoise_h=10.0, gamma=0.72, clahe_clip=2.0, clahe_tile=8,
        saturation=1.20, s_curve_shadow=0.06, s_curve_highlight=0.03,
        s_curve_contrast=1.12, bg_filter_size=64,
        unsharp_amount=1.0, unsharp_radius=2.5,
    ),
    "none": PostProcessConfig(),
}


# ---------------------------------------------------------------------------
# Alinhamento ECC
# ---------------------------------------------------------------------------

def align_ecc_multiscale(
    reference_gray: np.ndarray,
    target_gray: np.ndarray,
    config: AlignConfig,
) -> np.ndarray | None:
    """Alinha target ao reference usando ECC multi-resolucao."""
    warp_matrix = np.eye(2, 3, dtype=np.float32)

    for level in range(config.ecc_pyramid_levels, 0, -1):
        scale = 1.0 / (2 ** (level - 1))
        ref_scaled = cv2.resize(reference_gray, None, fx=scale, fy=scale,
                                interpolation=cv2.INTER_AREA)
        tgt_scaled = cv2.resize(target_gray, None, fx=scale, fy=scale,
                                interpolation=cv2.INTER_AREA)

        level_warp = warp_matrix.copy()
        level_warp[0, 2] *= scale
        level_warp[1, 2] *= scale

        criteria = (cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT,
                    config.ecc_iterations, config.ecc_epsilon)

        try:
            _, level_warp = cv2.findTransformECC(
                ref_scaled, tgt_scaled, level_warp,
                cv2.MOTION_AFFINE, criteria, None, 5,
            )
        except cv2.error:
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

        level_warp[0, 2] /= scale
        level_warp[1, 2] /= scale
        warp_matrix = level_warp

    return warp_matrix


def prepare_alignment_gray(image: np.ndarray, max_dimension: int) -> np.ndarray:
    """Prepara grayscale para alinhamento."""
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

    if max_dimension > 0:
        h, w = gray.shape[:2]
        if max(h, w) > max_dimension:
            scale = max_dimension / max(h, w)
            gray = cv2.resize(gray, None, fx=scale, fy=scale,
                              interpolation=cv2.INTER_AREA)

    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    return clahe.apply(gray)


def warp_image(image: np.ndarray, warp_matrix: np.ndarray,
               output_size: tuple[int, int]) -> np.ndarray:
    """Aplica warp affine com interpolacao de maxima qualidade."""
    return cv2.warpAffine(
        image, warp_matrix, output_size,
        flags=cv2.INTER_LANCZOS4 + cv2.WARP_INVERSE_MAP,
        borderMode=cv2.BORDER_CONSTANT, borderValue=0,
    )


# ---------------------------------------------------------------------------
# Stacking (float32 para maxima precisao)
# ---------------------------------------------------------------------------

def mean_stack(images: list[np.ndarray]) -> np.ndarray:
    """Stack por media aritmetica em float32."""
    stacked = np.mean(images, axis=0)
    return np.clip(stacked, 0, 255).astype(np.uint8)


def median_stack(images: list[np.ndarray]) -> np.ndarray:
    """Stack por mediana (remove outliers)."""
    stacked = np.median(images, axis=0)
    return np.clip(stacked, 0, 255).astype(np.uint8)


# ---------------------------------------------------------------------------
# Post-processamento (float32 pipeline para evitar banding)
# ---------------------------------------------------------------------------

def _to_float(img: np.ndarray) -> tuple[np.ndarray, bool]:
    """Converte para float32 [0,1] se necessario. Retorna (img, was_uint8)."""
    if img.dtype == np.uint8:
        return img.astype(np.float32) / 255.0, True
    return img.astype(np.float32), False


def _to_output(img: np.ndarray, was_uint8: bool) -> np.ndarray:
    """Converte de volta para uint8 se a entrada era uint8.
    Usa dithering de 0.5 LSB para evitar banding na conversao final."""
    if was_uint8:
        # Add 0.5/255 noise before truncation = triangular dither (1 LSB p-p)
        dither = (np.random.default_rng().random(img.shape, dtype=np.float32) - 0.5) / 255.0
        return np.clip((img + dither) * 255.0, 0, 255).astype(np.uint8)
    return img


def apply_gamma_f32(img_f: np.ndarray, gamma: float) -> np.ndarray:
    """Gamma em float32."""
    if abs(gamma - 1.0) < 0.001:
        return img_f
    return np.power(np.maximum(img_f, 0.0), gamma)


def apply_clahe_f32(img_f: np.ndarray, clip_limit: float, tile_size: int,
                    was_uint8: bool) -> np.ndarray:
    """
    CLAHE em uint8 (unico jeito no OpenCV), depois volta pra float32.
    Isso evita que o CLAHE cause posterizacao nos passos seguintes.
    """
    temp = np.clip(img_f * 255.0, 0, 255).astype(np.uint8)
    lab = cv2.cvtColor(temp, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=clip_limit, tileGridSize=(tile_size, tile_size))
    l_eq = clahe.apply(l)
    lab_eq = cv2.merge([l_eq, a, b])
    result_uint8 = cv2.cvtColor(lab_eq, cv2.COLOR_LAB2BGR)
    if was_uint8:
        return result_uint8.astype(np.float32) / 255.0
    return result_uint8.astype(np.float32) / 255.0


def apply_s_curve_f32(y: np.ndarray, shadow_boost: float,
                      highlight_dampen: float, midtone_contrast: float) -> np.ndarray:
    """S-curve em float32."""
    if abs(midtone_contrast - 1.0) > 0.001:
        y = 0.5 + (y - 0.5) * midtone_contrast
    if shadow_boost > 0.001:
        y = y + shadow_boost * np.square(1.0 - y)
    if highlight_dampen > 0.001:
        y = y - highlight_dampen * np.square(y)
    return np.clip(y, 0, 1)


def apply_saturation_f32(img_f: np.ndarray, saturation_scale: float) -> np.ndarray:
    """Saturacao em float32 com vibrance."""
    if abs(saturation_scale - 1.0) < 0.001:
        return img_f
    hsv = cv2.cvtColor(img_f, cv2.COLOR_BGR2HSV)
    h, s, v = cv2.split(hsv)
    weights = 1.0 - s
    scale = 1.0 + (saturation_scale - 1.0) * weights
    s = np.clip(s * scale, 0, 1)
    return cv2.cvtColor(cv2.merge([h, s, v]), cv2.COLOR_HSV2BGR)


def apply_unsharp_f32(img_f: np.ndarray, amount: float, radius: float) -> np.ndarray:
    """Unsharp mask em float32."""
    if amount < 0.01:
        return img_f
    blurred = cv2.GaussianBlur(img_f, (0, 0), radius)
    return np.clip(img_f + (img_f - blurred) * amount, 0, 1)


def remove_background_gradient(
    img: np.ndarray, filter_size: int, strength: float = 0.85,
) -> np.ndarray:
    """Remove gradiente de fundo (poluicao luminosa)."""
    if filter_size < 3:
        return img
    was_uint8 = img.dtype == np.uint8
    img_f, _ = _to_float(img)

    gray = cv2.cvtColor((img_f * 255).astype(np.uint8), cv2.COLOR_BGR2GRAY)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (filter_size, filter_size))
    background = cv2.morphologyEx(gray, cv2.MORPH_OPEN, kernel)
    background = cv2.GaussianBlur(background, (filter_size | 1, filter_size | 1), 0)
    bg_f = background.astype(np.float32) / 255.0
    mean_bg = float(np.mean(bg_f))

    result = img_f.copy()
    for c in range(3):
        result[:, :, c] = result[:, :, c] - (bg_f - mean_bg) * strength

    if was_uint8:
        return np.clip(result * 255.0, 0, 255).astype(np.uint8)
    return np.clip(result, 0, 1)


def post_process(
    image: np.ndarray,
    config: PostProcessConfig,
    denoiser: str = "fastnlm",
    deepsnr_bin: str | None = None,
    tmp_dir: str | None = None,
) -> np.ndarray:
    """
    Pipeline de pos-processamento em float32 para maxima qualidade.
    Apenas CLAHE e denoise usam uint8 internamente (limitacao do OpenCV);
    os resultados voltam para float32 imediatamente.

    denoiser: "fastnlm" (OpenCV) ou "deepsnr" (IA / CoreML)
    """
    if config.denoise_hColor is None:
        config.denoise_hColor = config.denoise_h

    img_f, is_uint8 = _to_float(image)

    # 1. Background extraction
    if config.bg_filter_size > 0:
        img_f, _ = _to_float(
            remove_background_gradient(
                (img_f * 255).astype(np.uint8), config.bg_filter_size,
            )
        )

    # 2. Gamma
    if config.gamma > 0.01:
        img_f = apply_gamma_f32(img_f, config.gamma)

    # 3. CLAHE (uint8 roundtrip, volta pra float32)
    if config.clahe_clip > 0.01:
        img_f = apply_clahe_f32(img_f, config.clahe_clip, config.clahe_tile, is_uint8)

    # 4. S-curve
    if (config.s_curve_shadow > 0.001 or config.s_curve_highlight > 0.001
            or abs(config.s_curve_contrast - 1.0) > 0.001):
        img_f = apply_s_curve_f32(
            img_f, config.s_curve_shadow,
            config.s_curve_highlight, config.s_curve_contrast,
        )

    # 5. Saturation
    if config.saturation > 0.01 and abs(config.saturation - 1.0) > 0.001:
        img_f = apply_saturation_f32(img_f, config.saturation)

    # 6. Unsharp mask
    if config.unsharp_amount > 0.01:
        img_f = apply_unsharp_f32(img_f, config.unsharp_amount, config.unsharp_radius)

    # 7. Denoise
    if config.denoise_h > 0:
        temp_uint8 = np.clip(img_f * 255.0, 0, 255).astype(np.uint8)

        if denoiser == "deepsnr" and deepsnr_bin:
            denoised = denoise_deepsnr(temp_uint8, deepsnr_bin, tmp_dir=tmp_dir)
        else:
            denoised = cv2.fastNlMeansDenoisingColored(
                temp_uint8, None, config.denoise_h, config.denoise_hColor, 7, 21,
            )

        # Voltar pra float32 para saida de alta qualidade
        img_f = denoised.astype(np.float32) / 255.0

    # 8. Voltar pra uint8 com dithering
    return _to_output(img_f, is_uint8)


# -- DeepSNR (IA denoiser) ----------------------------------------------------

def denoise_deepsnr(
    image: np.ndarray,
    deepsnr_bin: str,
    model: int = 2,
    stride: int = 480,
    tmp_dir: str | None = None,
) -> np.ndarray:
    """
    Aplica DeepSNR (IA) na imagem. Salva como TIFF temporario,
    executa o CLI deepsnr, carrega o resultado de volta.
    """
    import tempfile as tmpmod

    tmp_input = Path(tmp_dir or tmpmod.gettempdir()) / f"deepsnr_in_{os.getpid()}_{id(image)}.tiff"
    tmp_output = Path(tmp_dir or tmpmod.gettempdir()) / f"deepsnr_out_{os.getpid()}_{id(image)}.tiff"

    try:
        cv2.imwrite(str(tmp_input), image)

        cmd = [
            deepsnr_bin,
            "--input", str(tmp_input),
            "--output", str(tmp_output),
            "--model", str(model),
            "--stride", str(stride),
            "--quiet",
        ]
        subprocess.run(cmd, check=True, capture_output=True, text=True, timeout=300)

        result = cv2.imread(str(tmp_output), cv2.IMREAD_COLOR)
        if result is None:
            raise RuntimeError(f"DeepSNR produziu saida invalida: {tmp_output}")

        return result

    finally:
        for p in [tmp_input, tmp_output]:
            if p.exists():
                p.unlink(missing_ok=True)


def find_deepsnr_bin(custom_path: str | None = None) -> str | None:
    """Encontra o executavel deepsnr."""
    if custom_path:
        p = Path(custom_path)
        if p.is_file():
            return str(p.resolve())
        if (p / "deepsnr").is_file():
            return str((p / "deepsnr").resolve())

    # Procurar em /tmp por downloads recentes
    import glob as gmod
    for pattern in ["/tmp/deepsnr/**/deepsnr", "/tmp/deepsnr*/**/deepsnr"]:
        for found in gmod.glob(pattern, recursive=True):
            if os.path.isfile(found) and os.access(found, os.X_OK):
                return found

    candidates = ["/usr/local/bin/deepsnr", "/usr/bin/deepsnr", "/opt/homebrew/bin/deepsnr"]
    for c in candidates:
        if os.path.isfile(c) and os.access(c, os.X_OK):
            return c

    return None


# ---------------------------------------------------------------------------
# Processar um grupo de frames
# ---------------------------------------------------------------------------

def process_frame_group(
    frame_paths: list[Path],
    align_config: AlignConfig,
    post_config: PostProcessConfig,
    stack_method: str = "mean",
    denoiser: str = "fastnlm",
    deepsnr_bin: str | None = None,
    tmp_dir: str | None = None,
) -> np.ndarray | None:
    """
    Processa um grupo de frames: alinha, stack, pos-processa.
    Retorna o frame processado (uint8 BGR) ou None se falhar.
    """
    if len(frame_paths) < 2:
        # Se so tem 1 frame, nao faz stack, so pos-processa
        color = cv2.imread(str(frame_paths[0]), cv2.IMREAD_COLOR)
        if color is None:
            return None
        return post_process(color, post_config, denoiser=denoiser, deepsnr_bin=deepsnr_bin, tmp_dir=tmp_dir)

    # Carregar reference (primeiro frame)
    reference_color = cv2.imread(str(frame_paths[0]), cv2.IMREAD_COLOR)
    if reference_color is None:
        return None

    h_full, w_full = reference_color.shape[:2]

    # Preparar reference para alinhamento
    reference_gray = prepare_alignment_gray(reference_color, align_config.max_dimension)

    # Reduzir reference_color se necessario
    if align_config.max_dimension > 0:
        if max(h_full, w_full) > align_config.max_dimension:
            scale = align_config.max_dimension / max(h_full, w_full)
            w_aligned = int(w_full * scale)
            h_aligned = int(h_full * scale)
            reference_color = cv2.resize(
                reference_color, (w_aligned, h_aligned),
                interpolation=cv2.INTER_AREA,
            )
        else:
            w_aligned, h_aligned = w_full, h_full
    else:
        w_aligned, h_aligned = w_full, h_full

    aligned_frames = [reference_color]

    # Alinhar frames restantes
    for path in frame_paths[1:]:
        color = cv2.imread(str(path), cv2.IMREAD_COLOR)
        if color is None:
            continue

        gray_proc = prepare_alignment_gray(color, align_config.max_dimension)
        warp = align_ecc_multiscale(reference_gray, gray_proc, align_config)

        if warp is None:
            continue

        # Reduzir se necessario
        if align_config.max_dimension > 0:
            h, w = color.shape[:2]
            if max(h, w) > align_config.max_dimension:
                scale = align_config.max_dimension / max(h, w)
                color = cv2.resize(
                    color, (int(w * scale), int(h * scale)),
                    interpolation=cv2.INTER_AREA,
                )

        aligned = warp_image(color, warp, (w_aligned, h_aligned))
        aligned_frames.append(aligned)

    if len(aligned_frames) < 2:
        # Fallback: so pos-processa o primeiro frame
        return post_process(reference_color, post_config, denoiser=denoiser, deepsnr_bin=deepsnr_bin, tmp_dir=tmp_dir)

    # Stack
    if stack_method == "mean":
        stacked = mean_stack(aligned_frames)
    elif stack_method == "median":
        stacked = median_stack(aligned_frames)
    else:
        stacked = mean_stack(aligned_frames)

    # Post-process
    return post_process(stacked, post_config, denoiser=denoiser, deepsnr_bin=deepsnr_bin, tmp_dir=tmp_dir)


# ---------------------------------------------------------------------------
# Encode MP4 com ffmpeg
# ---------------------------------------------------------------------------

def encode_mp4(
    frames_dir: Path,
    output_path: Path,
    fps: int = 24,
    crf: int = 15,
    preset: str = "medium",
    pixel_format: str = "yuv420p",
    input_pattern: str = "frame_%06d.png",
) -> bool:
    """
    Codifica PNGs para MP4 com ffmpeg, maxima qualidade.
    crf 15 = visualmente indistinguivel do original para video 8-bit.
    yuv420p = compatibilidade universal; use yuv444p para maxima Cor.
    """
    cmd = [
        "ffmpeg", "-y",
        "-framerate", str(fps),
        "-i", str(frames_dir / input_pattern),
        "-c:v", "libx264",
        "-crf", str(crf),
        "-preset", preset,
        "-pix_fmt", pixel_format,
        "-color_primaries", "bt709",
        "-color_trc", "bt709",
        "-colorspace", "bt709",
        "-movflags", "+faststart",
        "-x264-params", "no-deblock=1:keyint=60:min-keyint=30",
        str(output_path),
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  ffmpeg error:\n{result.stderr}", file=sys.stderr)
        return False
    return True


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def find_frames(directory: Path) -> list[Path]:
    """Encontra frames JPG no diretorio, ordenados."""
    return sorted(
        p for p in directory.iterdir()
        if p.suffix.lower() in (".jpg", ".jpeg")
    )


def main():
    parser = argparse.ArgumentParser(
        description="Renderiza timelapse astro completo → MP4 de alta qualidade",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Exemplos:
  %(prog)s ~/frames
      Stack de 10 frames por grupo, preset natural, 24fps, full resolution

  %(prog)s ~/frames --stack-size 15 --preset balanced --fps 30
      Grupos de 15 frames, processamento medio, 30fps

  %(prog)s ~/frames --stack-size 5 --preset none --no-denoise --fps 60
      Stack rapido sem pos-processamento, 60fps (util para preview)

  %(prog)s ~/frames --stack-size 20 --max-dim 3840 --crf 12 --pixfmt yuv444p
      Qualidade maxima: 4K, CRF 12, 4:4:4 chroma (arquivos grandes!)
        """,
    )
    # -- I/O
    parser.add_argument("directory", type=str,
                        help="Diretorio com frames JPG do timelapse")
    parser.add_argument("--output", "-o", type=str, default=None,
                        help="Arquivo MP4 de saida (default: <dir>/_render/astro.mp4)")

    # -- Stacking
    parser.add_argument("--stack-size", "-n", type=int, default=10,
                        help="Frames por stack (default: 10)")
    parser.add_argument("--stack", "-s", choices=["mean", "median"], default="mean",
                        help="Metodo de stacking (default: mean)")
    parser.add_argument("--max-dim", type=int, default=0,
                        help="Dimensao maxima (0 = full resolution, default: 0)")

    # -- Post-processamento
    parser.add_argument("--preset", "-p",
                        choices=["natural", "light", "balanced", "strong", "none"],
                        default="natural",
                        help="Preset de pos-processamento (default: natural)")
    parser.add_argument("--denoise", "-d", type=float, default=None,
                        help="Forca do denoise h (sobrescreve o preset)")
    parser.add_argument("--no-denoise", action="store_true",
                        help="Desliga o denoise")
    parser.add_argument("--denoiser", choices=["fastnlm", "deepsnr"], default="fastnlm",
                        help="Motor de denoise: fastnlm (OpenCV) ou deepsnr (IA/CoreML, default: fastnlm)")
    parser.add_argument("--deepsnr-bin", type=str, default=None,
                        help="Caminho do executavel deepsnr (auto-detecta se omitido)")
    parser.add_argument("--gamma", type=float, default=None,
                        help="Gamma (< 1 clareia)")
    parser.add_argument("--clahe", type=float, default=None,
                        help="CLAHE clip limit")
    parser.add_argument("--saturation", type=float, default=None,
                        help="Escala de saturacao")
    parser.add_argument("--unsharp", type=float, default=None,
                        help="Unsharp mask amount")

    # -- Video
    parser.add_argument("--fps", type=int, default=24,
                        help="Frames por segundo (default: 24)")
    parser.add_argument("--crf", type=int, default=15,
                        help="Qualidade x264 CRF (0-51, menor=m melhor, default: 15)")
    parser.add_argument("--pixfmt", choices=["yuv420p", "yuv444p"], default="yuv420p",
                        help="Pixel format (default: yuv420p, yuv444p = max chroma)")
    parser.add_argument("--ffmpeg-preset", choices=["fast", "medium", "slow", "veryslow"],
                        default="medium",
                        help="Preset do ffmpeg (default: medium)")

    # -- Outros
    parser.add_argument("--start-group", type=int, default=0,
                        help="Comecar do grupo N (0-based, util para resume)")
    parser.add_argument("--max-groups", type=int, default=0,
                        help="Maximo de grupos a processar (0 = todos)")
    parser.add_argument("--keep-pngs", action="store_true",
                        help="Manter PNGs intermediarios (nao apagar apos encode)")

    args = parser.parse_args()

    # -- Validar ---------------------------------------------------------------
    directory = Path(args.directory).expanduser().resolve()
    if not directory.is_dir():
        print(f"ERRO: Diretorio nao encontrado: {directory}", file=sys.stderr)
        sys.exit(1)

    frames = find_frames(directory)
    if len(frames) < 2:
        print(f"ERRO: Apenas {len(frames)} frames (min: 2)", file=sys.stderr)
        sys.exit(1)

    # -- Config ----------------------------------------------------------------
    if args.output:
        output_mp4 = Path(args.output).expanduser().resolve()
        render_dir = output_mp4.parent / "_render_frames"
    else:
        render_dir = directory / "_render" / "frames"
        output_mp4 = directory / "_render" / "astro.mp4"

    render_dir.mkdir(parents=True, exist_ok=True)
    output_mp4.parent.mkdir(parents=True, exist_ok=True)

    # -- Detectar DeepSNR -------------------------------------------------------
    deepsnr_bin = None
    if args.denoiser == "deepsnr":
        deepsnr_bin = find_deepsnr_bin(args.deepsnr_bin)
        if deepsnr_bin is None:
            print("ERRO: --denoiser deepsnr mas executavel deepsnr nao encontrado.",
                  file=sys.stderr)
            print("  Use --deepsnr-bin <caminho> ou instale o DeepSNR CLI.",
                  file=sys.stderr)
            print("  Download: https://starnetastro.com/cli-tools/deepsnr/",
                  file=sys.stderr)
            sys.exit(1)
        print(f"  DeepSNR:           {deepsnr_bin}")
        # Criar dir temporario para TIFFs do DeepSNR
        deepsnr_tmp = render_dir.parent / "tmp"
        deepsnr_tmp.mkdir(parents=True, exist_ok=True)
    else:
        deepsnr_tmp = None

    # Alinhamento: usar metade do max-dim para referencia (mais rapido, mesma precisao)
    align_max_dim = args.max_dim if args.max_dim > 0 else 0
    # Para full-res, alinhar com referencia reduzida a 1920px pra velocidade
    if align_max_dim == 0:
        align_max_dim = 1920  # referencia reduzida, warp aplicado em full-res

    align_config = AlignConfig(max_dimension=align_max_dim)

    # Post-processamento
    if args.preset in PRESETS:
        pp = PRESETS[args.preset]
    else:
        pp = PostProcessConfig()

    if args.no_denoise:
        pp.denoise_h = 0.0
    if args.denoise is not None:
        pp.denoise_h = args.denoise
    if args.gamma is not None:
        pp.gamma = args.gamma
    if args.clahe is not None:
        pp.clahe_clip = args.clahe
    if args.saturation is not None:
        pp.saturation = args.saturation
    if args.unsharp is not None:
        pp.unsharp_amount = args.unsharp

    # -- Agrupar frames --------------------------------------------------------
    stack_size = max(2, args.stack_size)
    groups = []
    for i in range(0, len(frames), stack_size):
        group = frames[i:i + stack_size]
        if len(group) >= 2 or (len(group) == 1 and len(groups) > 0):
            groups.append(group)

    total_groups = len(groups)
    start_group = max(0, min(args.start_group, total_groups - 1))
    end_group = (start_group + args.max_groups) if args.max_groups > 0 else total_groups
    groups = groups[start_group:end_group]

    print(f"Render astro → MP4")
    print(f"  Frames origem:     {len(frames)}")
    print(f"  Stack size:        {stack_size}")
    print(f"  Grupos:            {total_groups} (processando {len(groups)})")
    print(f"  Resolucao:         {'full' if args.max_dim == 0 else f'{args.max_dim}px'}")
    print(f"  Align reference:   {align_max_dim}px")
    print(f"  Preset:            {args.preset}")
    print(f"  Denoise:           h={pp.denoise_h}" + (" (off)" if pp.denoise_h == 0 else "") +
          f" [{args.denoiser}]")
    print(f"  FPS:               {args.fps}")
    print(f"  CRF:               {args.crf}")
    print(f"  Pixel format:      {args.pixfmt}")
    print(f"  Output:            {output_mp4}")
    print()

    # -- Processar cada grupo --------------------------------------------------
    t0 = time.perf_counter()
    png_paths = []
    success_count = 0
    bar_width = 30  # largura da barra de progresso em caracteres

    for idx, group in enumerate(groups):
        group_num = start_group + idx + 1
        png_path = render_dir / f"frame_{group_num:06d}.png"
        png_paths.append(png_path)

        # Pular se ja existe (resume)
        if png_path.exists():
            success_count += 1
            elapsed = time.perf_counter() - t0
            ratio = (idx + 1) / len(groups)
            pct = ratio * 100
            filled = int(bar_width * ratio)
            bar = "█" * filled + "░" * (bar_width - filled)
            rpm = (idx + 1) / elapsed * 60 if elapsed > 0 else 0
            eta = (len(groups) - idx - 1) / (rpm / 60) if rpm > 0 else 0
            print(f"\r  [{bar}] {pct:5.1f}%  {group_num}/{start_group + len(groups)}  "
                  f"{rpm:.1f} grp/min  ETA {eta:.0f}s  "
                  f"(reutilizado)", end="", flush=True)
            continue

        processed = process_frame_group(
            group, align_config, pp, args.stack,
            denoiser=args.denoiser,
            deepsnr_bin=deepsnr_bin,
            tmp_dir=str(render_dir.parent / "tmp"),
        )

        if processed is not None:
            cv2.imwrite(str(png_path), processed, [
                cv2.IMWRITE_PNG_COMPRESSION, 1,
            ])
            success_count += 1

        # Barra de progresso
        elapsed = time.perf_counter() - t0
        ratio = (idx + 1) / len(groups)
        pct = ratio * 100
        filled = int(bar_width * ratio)
        bar = "█" * filled + "░" * (bar_width - filled)
        rpm = (idx + 1) / elapsed * 60 if elapsed > 0 else 0
        eta = (len(groups) - idx - 1) / (rpm / 60) if rpm > 0 else 0
        ok_str = "OK" if processed is not None else "FAIL"
        print(f"\r  [{bar}] {pct:5.1f}%  {group_num}/{start_group + len(groups)}  "
              f"{rpm:.1f} grp/min  ETA {eta:.0f}s  {ok_str}", end="", flush=True)

    print()
    elapsed = time.perf_counter() - t0
    print(f"  Processamento: {elapsed:.0f}s ({success_count}/{len(groups)} grupos)")

    if success_count == 0:
        print("ERRO: Nenhum frame processado", file=sys.stderr)
        sys.exit(1)

    # -- Encode MP4 ------------------------------------------------------------
    print(f"\n  Codificando MP4 (CRF={args.crf}, {args.pixfmt})...")
    t1 = time.perf_counter()

    ok = encode_mp4(
        render_dir, output_mp4,
        fps=args.fps, crf=args.crf,
        pixel_format=args.pixfmt,
        preset=args.ffmpeg_preset,
    )

    if not ok:
        print("ERRO: Falha na codificacao ffmpeg", file=sys.stderr)
        sys.exit(1)

    encode_time = time.perf_counter() - t1
    mp4_size = output_mp4.stat().st_size if output_mp4.exists() else 0

    # -- Cleanup ---------------------------------------------------------------
    if not args.keep_pngs and ok:
        shutil.rmtree(render_dir)
        print(f"  PNGs temporarios removidos")
    else:
        print(f"  PNGs mantidos em: {render_dir}")

    # -- Relatorio -------------------------------------------------------------
    total_time = time.perf_counter() - t0
    print(f"\n{'='*60}")
    print(f"MP4 PRONTO")
    print(f"{'='*60}")
    print(f"  Arquivo:      {output_mp4}")
    print(f"  Tamanho:      {mp4_size / 1024 / 1024:.1f} MB")
    print(f"  Grupos:       {success_count}")
    print(f"  Duracao:      {success_count / args.fps:.1f}s")
    print(f"  FPS:          {args.fps}")
    print(f"  CRF:          {args.crf}")
    print(f"  Chroma:       {args.pixfmt}")
    print(f"  Tempo total:  {total_time:.0f}s")


if __name__ == "__main__":
    main()
