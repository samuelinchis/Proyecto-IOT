############################################################
# Pipeline IoT: Lambda publicadora -> S3 -> Lambda ingestora -> DynamoDB
#
# Este repo SOLO crea la infraestructura. El código de las lambdas
# vive en la carpeta ../lambdas y se despliega con deploy.sh.
############################################################

# Versiones de los proveedores fijadas para que no cambien solas.
terraform {
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.0" }
    archive = { source = "hashicorp/archive" }
  }
}

# Proveedor AWS: región donde se crean todos los recursos.
provider "aws" {
  region = "us-east-1"
}

# En AWS Learner Lab no se pueden crear roles IAM, así que usamos
# el rol existente "LabRole" (lo leemos con un data source, no lo creamos).
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

# ---------------------------------------------------------
# 1. Bucket S3 donde la lambda publicadora deja los eventos JSON
# ---------------------------------------------------------
# ¿Por qué no usamos el recurso "aws_s3_bucket"?
# Cada vez que lo lee (plan/apply/refresh), el proveedor AWS consulta la
# configuración de "Object Lock" del bucket (s3:GetBucketObjectLockConfiguration).
# En Learner Lab esa consulta está prohibida por una SCP de la organización,
# así que el plan/apply falla aunque el bucket no use Object Lock.
#
# Solución: crear y borrar el bucket con la AWS CLI desde un "terraform_data".
# Terraform sigue controlando su ciclo de vida (apply lo crea, destroy lo
# borra), pero nunca lee sus configuraciones.

# Cuenta actual: su ID hace único el nombre del bucket (los nombres de S3
# son únicos en todo el mundo).
data "aws_caller_identity" "actual" {}

locals {
  region = "us-east-1"
}

resource "terraform_data" "bucket_eventos" {
  # Lo que se guarda en "input" queda disponible como self.input al destruir
  # y como .output para el resto de recursos.
  input = "iot-eventos-${data.aws_caller_identity.actual.account_id}"

  # Al crear: crea el bucket (en us-east-1 no se indica LocationConstraint).
  provisioner "local-exec" {
    command = "aws s3api create-bucket --bucket ${self.input} --region ${local.region}"
  }

  # Al destruir: borra el bucket y todos sus objetos (--force).
  # Un provisioner de destroy solo puede usar "self", por eso la región va fija.
  provisioner "local-exec" {
    when    = destroy
    command = "aws s3 rb s3://${self.input} --force --region us-east-1"
  }
}

locals {
  # Usar .output (y no el texto directo) crea la dependencia: los recursos
  # que usen estos valores esperan a que el bucket exista.
  bucket_name = terraform_data.bucket_eventos.output
  bucket_arn  = "arn:aws:s3:::${terraform_data.bucket_eventos.output}"
}

# ---------------------------------------------------------
# 2. Tabla DynamoDB donde se guardan las lecturas de temperatura
# ---------------------------------------------------------
resource "aws_dynamodb_table" "lecturas" {
  name         = "iot_lecturas"
  billing_mode = "PAY_PER_REQUEST" # Sin capacidad que aprovisionar: ideal para laboratorios

  # Clave de partición: un sensor agrupa todas sus lecturas.
  hash_key = "device_id"
  # Clave de ordenamiento: permite consultar lecturas de un sensor por fecha.
  range_key = "timestamp"

  attribute {
    name = "device_id"
    type = "S" # S = String
  }

  attribute {
    name = "timestamp"
    type = "S"
  }
}

# ---------------------------------------------------------
# 3. Código "vacío" inicial para crear las lambdas
# ---------------------------------------------------------
# Terraform exige un zip para crear una lambda. Usamos uno mínimo y el
# código real se sube después con deploy.sh (aws lambda update-function-code).
data "archive_file" "dummy_zip" {
  type        = "zip"
  output_path = "${path.module}/dummy.zip"

  source {
    content  = "def lambda_handler(event, context): pass"
    filename = "lambda_function.py"
  }
}

# ---------------------------------------------------------
# 4. Lambda publicadora: simula un sensor y escribe el JSON en S3
# ---------------------------------------------------------
resource "aws_lambda_function" "publicadora" {
  function_name = "iot_publisher_lambda"
  role          = data.aws_iam_role.lab_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = 10

  filename         = data.archive_file.dummy_zip.output_path
  source_code_hash = data.archive_file.dummy_zip.output_base64sha256

  # Variables de entorno: así el código no tiene el nombre del bucket "quemado".
  environment {
    variables = {
      BUCKET_NAME = local.bucket_name
    }
  }

  # Como el código se actualiza fuera de Terraform, ignoramos esos cambios
  # para que un "terraform apply" no sobrescriba el código desplegado.
  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

# ---------------------------------------------------------
# 5. Lambda ingestora: se dispara desde S3 y escribe en DynamoDB
# ---------------------------------------------------------
resource "aws_lambda_function" "ingestora" {
  function_name = "iot_ingestor_lambda"
  role          = data.aws_iam_role.lab_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = 10

  filename         = data.archive_file.dummy_zip.output_path
  source_code_hash = data.archive_file.dummy_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.lecturas.name
    }
  }

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

# ---------------------------------------------------------
# 6. Trigger S3 -> Lambda ingestora
# ---------------------------------------------------------
# Primero: permiso para que el servicio S3 pueda invocar la lambda.
resource "aws_lambda_permission" "permitir_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingestora.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = local.bucket_arn
}

# Segundo: notificación del bucket. Cada objeto nuevo en events/*.json
# dispara la lambda ingestora.
resource "aws_s3_bucket_notification" "notificacion" {
  bucket = local.bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.ingestora.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "events/"
    filter_suffix       = ".json"
  }

  # El permiso debe existir antes de crear la notificación.
  depends_on = [aws_lambda_permission.permitir_s3]
}

# ---------------------------------------------------------
# Salidas: valores útiles que deploy.sh y el Makefile pueden consultar
# ---------------------------------------------------------
output "bucket_name" {
  value = local.bucket_name
}

output "table_name" {
  value = aws_dynamodb_table.lecturas.name
}

output "publisher_function_name" {
  value = aws_lambda_function.publicadora.function_name
}

output "ingestor_function_name" {
  value = aws_lambda_function.ingestora.function_name
}
