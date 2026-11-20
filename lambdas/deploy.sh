#!/bin/bash
# Despliega el código de las lambdas (las funciones las crea ../infraestructura con Terraform).
# Uso: ./deploy.sh <publisher|ingestor|all>
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
REGION="${AWS_REGION:-us-east-1}"

deploy_function() {
  local name="$1"                          # publisher | ingestor
  local function_name="iot_${name}_lambda"
  local build_dir
  build_dir="$(mktemp -d)"
  local zip_file="$build_dir/lambda_function.zip"

  echo "==> Empaquetando $name"
  (cd "$ROOT_DIR/src/$name" && zip -q "$zip_file" lambda_function.py)

  if ! aws lambda get-function --function-name "$function_name" --region "$REGION" >/dev/null 2>&1; then
    echo "Error: la función $function_name no existe. Ejecuta primero 'make infra-apply'." >&2
    rm -rf "$build_dir"; exit 1
  fi

  echo "==> Subiendo código a $function_name"
  aws lambda update-function-code --function-name "$function_name" \
    --zip-file "fileb://$zip_file" --region "$REGION" --query '[FunctionName,LastModified]' --output text
  aws lambda wait function-updated --function-name "$function_name" --region "$REGION"
  rm -rf "$build_dir"
  echo "==> $function_name desplegada"
}

case "${1:-}" in
  publisher|ingestor) deploy_function "$1" ;;
  all) deploy_function publisher; deploy_function ingestor ;;
  *) echo "Uso: $0 <publisher|ingestor|all>" >&2; exit 1 ;;
esac
