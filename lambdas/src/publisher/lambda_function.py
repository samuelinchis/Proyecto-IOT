"""Lambda publicadora: simula una lectura de un sensor de temperatura
y la publica como archivo JSON en S3."""
import json
import os
import random
import uuid
from datetime import datetime, timezone

import boto3

s3 = boto3.client("s3")


def lambda_handler(event, context):
    bucket = os.environ["BUCKET_NAME"]
    event = event or {}
    device_id = event.get("device_id", "sensor-01")

    lectura = {
        "device_id": device_id,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "temperature": round(random.uniform(18.0, 35.0), 2),
        "humidity": round(random.uniform(30.0, 70.0), 2),
    }
    # Se permite fijar valores en la invocación (útil para pruebas)
    lectura.update({k: v for k, v in event.items() if k in lectura})

    key = f"events/{device_id}/{uuid.uuid4()}.json"
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(lectura),
        ContentType="application/json",
    )
    print(f"Publicado s3://{bucket}/{key}")
    return {"statusCode": 200, "body": json.dumps({"key": key, "lectura": lectura})}


def main():
    """Prueba local: llama al handler desde el PC contra el bucket real en AWS.

    Uso:
        BUCKET_NAME=<bucket> python lambda_function.py [device_id]

    El nombre del bucket se obtiene con:
        terraform -chdir=infraestructura output -raw bucket_name
    """
    import sys

    if "BUCKET_NAME" not in os.environ:
        sys.exit("Falta BUCKET_NAME")

    device_id = sys.argv[1] if len(sys.argv) > 1 else "sensor-01"
    resp = lambda_handler({"device_id": device_id}, None)
    print(json.dumps(json.loads(resp["body"]), indent=2))


if __name__ == "__main__":
    main()
