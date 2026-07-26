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

check_dependencies() {
  local missing=()
  local cmd

  for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Error: required command(s) not found in PATH: ${missing[*]}" >&2
    return 1
  fi

  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_dependencies
fi
