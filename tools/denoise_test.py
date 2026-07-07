#!/usr/bin/env python3
"""
Ferramenta local para testar reducao de ruido com OpenCV em frames de timelapse.

Aplica fastNlMeansDenoisingColored com 3 niveis de forca (leve/medio/forte)
no primeiro frame do diretorio e gera uma imagem de comparacao.

Uso:
    python3 denoise_test.py /caminho/para/sessao/frames
    python3 denoise_test.py /caminho/para/sessao/frames --frame 5
    python3 denoise_test.py /caminho/para/sessao/frames --strength 7

Dependencias (instalar uma vez):
    python3 -m venv .venv && source .venv/bin/activate
    pip install opencv-python numpy
"""

import argparse
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np


# ---------------------------------------------------------------------------
# Perfis de reducao de ruido
# ---------------------------------------------------------------------------
# h        = forca do filtro no canal de luminancia (maior = mais agressivo)
# hColor   = forca do filtro nos canais de cor
# template = tamanho do patch de comparacao (impar, 7 e um bom default)
# search   = tamanho da janela de busca (impar, 21 e um bom default)
# ---------------------------------------------------------------------------

@dataclass
class DenoisePreset:
    label: str
    h: float
    hColor: float
    template: int
    search: int


PRESETS = {
    "leve": DenoisePreset(
        label="Leve (h=3)",
        h=3,
        hColor=3,
        template=7,
        search=21,
    ),
    "medio": DenoisePreset(
        label="Medio (h=7)",
        h=7,
        hColor=7,
        template=7,
        search=21,
    ),
    "forte": DenoisePreset(
        label="Forte (h=12)",
        h=12,
        hColor=12,
        template=7,
        search=21,
    ),
    "extremo": DenoisePreset(
        label="Extremo (h=20)",
        h=20,
        hColor=20,
        template=7,
        search=21,
    ),
}


def find_first_frame(directory: Path) -> Path | None:
    """Encontra o primeiro frame JPG no diretorio (ordem alfabetica)."""
    jpgs = sorted(
        p for p in directory.iterdir()
        if p.suffix.lower() in (".jpg", ".jpeg")
    )
    return jpgs[0] if jpgs else None


def find_frame_by_index(directory: Path, index: int) -> Path | None:
    """Encontra o n-esimo frame JPG no diretorio (ordem alfabetica, 1-based)."""
    jpgs = sorted(
        p for p in directory.iterdir()
        if p.suffix.lower() in (".jpg", ".jpeg")
    )
    if 1 <= index <= len(jpgs):
        return jpgs[index - 1]
    return None


def apply_denoise(image: np.ndarray, preset: DenoisePreset) -> np.ndarray:
    """Aplica fastNlMeansDenoisingColored com os parametros do preset."""
    return cv2.fastNlMeansDenoisingColored(
        src=image,
        dst=None,
        h=preset.h,
        hColor=preset.hColor,
        templateWindowSize=preset.template,
        searchWindowSize=preset.search,
    )


def apply_custom_denoise(
    image: np.ndarray,
    h: float,
    hColor: float,
    template: int = 7,
    search: int = 21,
) -> np.ndarray:
    """Aplica fastNlMeansDenoisingColored com parametros customizados."""
    return cv2.fastNlMeansDenoisingColored(
        src=image,
        dst=None,
        h=h,
        hColor=hColor,
        templateWindowSize=template,
        searchWindowSize=search,
    )


def build_comparison_image(
    original: np.ndarray,
    results: dict[str, np.ndarray],
) -> np.ndarray:
    """Monta uma grade com original + resultados lado a lado (2x2)."""
    h, w = original.shape[:2]
    # Reduz tamanho de exibicao para caber na tela mantendo proporcao
    display_max = 800
    if max(h, w) > display_max:
        scale = display_max / max(h, w)
        new_w = int(w * scale)
        new_h = int(h * scale)
    else:
        new_w, new_h = w, h

    def resize(img: np.ndarray) -> np.ndarray:
        return cv2.resize(img, (new_w, new_h), interpolation=cv2.INTER_AREA)

    original_resized = resize(original)

    # Prepara textos sobre cada imagem
    def add_label(img: np.ndarray, text: str) -> np.ndarray:
        labeled = img.copy()
        font = cv2.FONT_HERSHEY_SIMPLEX
        font_scale = 0.7
        thickness = 2
        color = (255, 255, 255)
        # Fundo preto semi-transparente para legibilidade
        (tw, th), _ = cv2.getTextSize(text, font, font_scale, thickness)
        cv2.rectangle(
            labeled, (8, 8), (8 + tw + 8, 8 + th + 10), (0, 0, 0), -1,
        )
        cv2.putText(
            labeled, text, (12, 8 + th + 4), font, font_scale, color, thickness,
        )
        return labeled

    panels = [add_label(original_resized, "Original")]
    for key in ["leve", "medio", "forte"]:
        if key in results:
            panels.append(add_label(resize(results[key]), PRESETS[key].label))

    # Grade 2x2
    row1 = np.hstack(panels[:2])
    row2 = np.hstack(panels[2:4])
    comparison = np.vstack([row1, row2])

    return comparison


def build_single_comparison(
    original: np.ndarray,
    denoised: np.ndarray,
    denoise_label: str,
    zoom_roi: tuple[int, int, int, int] | None = None,
) -> np.ndarray:
    """Monta comparacao lado a lado: original | denoised, com zoom opcional."""
    h, w = original.shape[:2]
    display_max = 600
    if max(h, w) > display_max:
        scale = display_max / max(h, w)
        new_w = int(w * scale)
        new_h = int(h * scale)
    else:
        new_w, new_h = w, h

    original_small = cv2.resize(original, (new_w, new_h), interpolation=cv2.INTER_AREA)
    denoised_small = cv2.resize(denoised, (new_w, new_h), interpolation=cv2.INTER_AREA)

    # Diferenca amplificada (para ver o que foi removido)
    diff = cv2.absdiff(original_small, denoised_small)
    diff_amplified = cv2.convertScaleAbs(diff, alpha=8.0)

    # Labels
    font = cv2.FONT_HERSHEY_SIMPLEX
    font_scale = 0.6
    thickness = 2

    def add_text_label(img: np.ndarray, text: str) -> np.ndarray:
        out = img.copy()
        (tw, th), _ = cv2.getTextSize(text, font, font_scale, thickness)
        cv2.rectangle(out, (4, 4), (4 + tw + 8, 4 + th + 8), (0, 0, 0), -1)
        cv2.putText(out, text, (8, 4 + th + 4), font, font_scale, (255, 255, 255), thickness)
        return out

    row = np.hstack([
        add_text_label(original_small, "Original"),
        add_text_label(denoised_small, denoise_label),
        add_text_label(diff_amplified, "Ruido removido (8x)"),
    ])

    return row


def main():
    parser = argparse.ArgumentParser(
        description="Teste local de reducao de ruido OpenCV para frames de timelapse",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Exemplos:
  %(prog)s ~/Camerae/session_abc123
      Processa o primeiro frame com os 3 presets e gera comparacao 2x2

  %(prog)s ~/Camerae/session_abc123 --frame 10
      Usa o decimo frame em vez do primeiro

  %(prog)s ~/Camerae/session_abc123 --strength 5
      Testa com h=5 customizado em vez dos presets

  %(prog)s ~/Camerae/session_abc123 --single leve
      Gera comparacao individual (original | denoised | diff) so com leve
        """,
    )
    parser.add_argument(
        "directory",
        type=str,
        help="Diretorio com os frames JPG do timelapse",
    )
    parser.add_argument(
        "--frame", "-f",
        type=int,
        default=1,
        help="Numero do frame a processar (1-based, default: 1)",
    )
    parser.add_argument(
        "--output", "-o",
        type=str,
        default=None,
        help="Diretorio de saida (default: <directory>/_denoise_test)",
    )
    parser.add_argument(
        "--strength", "-s",
        type=float,
        default=None,
        help="Forca customizada h (ignora presets, testa so este valor)",
    )
    parser.add_argument(
        "--hColor",
        type=float,
        default=None,
        help="Forca de cor customizada (default: igual a h)",
    )
    parser.add_argument(
        "--template", "-t",
        type=int,
        default=7,
        help="Template window size (impar, default: 7)",
    )
    parser.add_argument(
        "--search", "-w",
        type=int,
        default=21,
        help="Search window size (impar, default: 21)",
    )
    parser.add_argument(
        "--single",
        type=str,
        choices=["leve", "medio", "forte", "extremo"],
        default=None,
        help="Gera comparacao individual com apenas um preset",
    )
    parser.add_argument(
        "--max-dimension",
        type=int,
        default=0,
        help="Reduz dimensao maxima antes de processar (0 = sem reducao, util para testes rapidos)",
    )

    args = parser.parse_args()

    # -----------------------------------------------------------------------
    # Validar entrada
    # -----------------------------------------------------------------------
    directory = Path(args.directory).expanduser().resolve()
    if not directory.is_dir():
        print(f"ERRO: Diretorio nao encontrado: {directory}", file=sys.stderr)
        sys.exit(1)

    frame_path = find_frame_by_index(directory, args.frame)
    if frame_path is None:
        print(f"ERRO: Nenhum frame JPG encontrado no diretorio (frame={args.frame})", file=sys.stderr)
        sys.exit(1)

    print(f"Frame selecionado: {frame_path.name}")
    print(f"Tamanho: {frame_path.stat().st_size / 1024 / 1024:.1f} MB")

    # -----------------------------------------------------------------------
    # Carregar imagem
    # -----------------------------------------------------------------------
    image = cv2.imread(str(frame_path), cv2.IMREAD_COLOR)
    if image is None:
        print(f"ERRO: Nao foi possivel ler a imagem: {frame_path}", file=sys.stderr)
        sys.exit(1)

    h, w = image.shape[:2]
    print(f"Dimensoes: {w}x{h}")

    if args.max_dimension > 0 and max(w, h) > args.max_dimension:
        scale = args.max_dimension / max(w, h)
        new_w = int(w * scale)
        new_h = int(h * scale)
        image = cv2.resize(image, (new_w, new_h), interpolation=cv2.INTER_AREA)
        print(f"Reduzido para: {new_w}x{new_h}")

    # -----------------------------------------------------------------------
    # Diretorio de saida
    # -----------------------------------------------------------------------
    if args.output:
        output_dir = Path(args.output).expanduser().resolve()
    else:
        output_dir = directory / "_denoise_test"
    output_dir.mkdir(parents=True, exist_ok=True)

    # -----------------------------------------------------------------------
    # Processar
    # -----------------------------------------------------------------------
    t0 = time.perf_counter()

    if args.strength is not None:
        # Modo customizado: testa um unico valor de h
        h = args.strength
        hColor = args.hColor if args.hColor is not None else h
        template = args.template
        search = args.search

        print(f"\nAplicando denoise customizado: h={h}, hColor={hColor}, template={template}, search={search}")
        denoised = apply_custom_denoise(image, h=h, hColor=hColor, template=template, search=search)

        elapsed = time.perf_counter() - t0
        print(f"Tempo: {elapsed:.1f}s")

        # Salvar resultado
        out_path = output_dir / f"denoise_h{h}_{frame_path.stem}.jpg"
        cv2.imwrite(str(out_path), denoised, [cv2.IMWRITE_JPEG_QUALITY, 95])
        print(f"Salvo: {out_path}")

        # Salvar comparacao individual
        comp = build_single_comparison(image, denoised, f"Denoise h={h}")
        comp_path = output_dir / f"comparison_h{h}_{frame_path.stem}.jpg"
        cv2.imwrite(str(comp_path), comp, [cv2.IMWRITE_JPEG_QUALITY, 92])
        print(f"Comparacao: {comp_path}")

    elif args.single:
        # Modo single: apenas um preset com comparacao detalhada
        preset = PRESETS[args.single]
        print(f"\nAplicando denoise {preset.label}")
        print(f"  h={preset.h}, hColor={preset.hColor}, template={preset.template}, search={preset.search}")

        denoised = apply_denoise(image, preset)

        elapsed = time.perf_counter() - t0
        print(f"Tempo: {elapsed:.1f}s")

        # Salvar denoised
        out_path = output_dir / f"denoise_{args.single}_{frame_path.stem}.jpg"
        cv2.imwrite(str(out_path), denoised, [cv2.IMWRITE_JPEG_QUALITY, 95])
        print(f"Salvo: {out_path}")

        # Salvar comparacao
        comp = build_single_comparison(image, denoised, preset.label)
        comp_path = output_dir / f"comparison_{args.single}_{frame_path.stem}.jpg"
        cv2.imwrite(str(comp_path), comp, [cv2.IMWRITE_JPEG_QUALITY, 92])
        print(f"Comparacao: {comp_path}")

    else:
        # Modo padrao: processa com os 3 presets e gera comparacao 2x2
        results: dict[str, np.ndarray] = {}

        for key in ["leve", "medio", "forte"]:
            preset = PRESETS[key]
            print(f"\nAplicando denoise {preset.label}...")
            sys.stdout.flush()

            t1 = time.perf_counter()
            denoised = apply_denoise(image, preset)
            dt = time.perf_counter() - t1

            results[key] = denoised
            print(f"  Tempo: {dt:.1f}s")

            # Salvar resultado individual
            out_path = output_dir / f"denoise_{key}_{frame_path.stem}.jpg"
            cv2.imwrite(str(out_path), denoised, [cv2.IMWRITE_JPEG_QUALITY, 95])

        # Comparacao 2x2
        print("\nGerando imagem de comparacao...")
        comparison = build_comparison_image(image, results)
        comp_path = output_dir / f"comparison_all_{frame_path.stem}.jpg"
        cv2.imwrite(str(comp_path), comparison, [cv2.IMWRITE_JPEG_QUALITY, 92])
        print(f"Comparacao: {comp_path}")

        # Tambem gera comparacoes individuais
        for key in ["leve", "medio", "forte"]:
            comp = build_single_comparison(image, results[key], PRESETS[key].label)
            comp_path = output_dir / f"comparison_{key}_{frame_path.stem}.jpg"
            cv2.imwrite(str(comp_path), comp, [cv2.IMWRITE_JPEG_QUALITY, 92])

    elapsed = time.perf_counter() - t0
    print(f"\nTempo total: {elapsed:.1f}s")
    print(f"Resultados em: {output_dir}")


if __name__ == "__main__":
    main()
