#!/usr/bin/env bash
# 等高線PMTiles生成パイプラインが依存するCLIツールがPATH上に存在するか確認する。
# 単体で実行した場合はその場でチェックを行い、他スクリプトからsourceされた場合は
# check_dependencies関数の定義のみを行う。

set -euo pipefail

REQUIRED_COMMANDS=(
  gdalbuildvrt
  gdal_contour
  mapshaper
  tippecanoe
  tile-join
  pmtiles
  python3
)

# 等高線の自己交差判定・距離計算をGEOS経由で高速に行うために使用する
# (純Pythonの総当たり判定は数千頂点規模のラインでは現実的な時間で終わらないため)
REQUIRED_PYTHON_MODULES=(
  shapely
)

check_dependencies() {
  local missing=()
  local cmd
  local module

  for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if command -v python3 >/dev/null 2>&1; then
    for module in "${REQUIRED_PYTHON_MODULES[@]}"; do
      if ! python3 -c "import ${module}" >/dev/null 2>&1; then
        missing+=("python3:${module}")
      fi
    done
  fi

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Error: required command(s)/module(s) not found: ${missing[*]}" >&2
    return 1
  fi

  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_dependencies
fi
