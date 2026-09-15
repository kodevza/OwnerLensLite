#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 -m venv "$ROOT_DIR/.venv-test"
source "$ROOT_DIR/.venv-test/bin/activate"
pip install -q -r "$ROOT_DIR/services/billing/requirements.txt" -r "$ROOT_DIR/services/payment/requirements.txt" pytest
pytest -q "$ROOT_DIR/tests"
