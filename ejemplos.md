# Plataforma IoT Serverless en AWS (S3, Lambda, DynamoDB y Chalice)

Pipeline de ingesta y consulta de lecturas de sensores IoT construido con **AWS Lambda**, **Amazon S3**, **Amazon DynamoDB**, **Amazon API Gateway** y **AWS Chalice**, diseñado para ejecutarse en entornos de laboratorio AWS utilizando `LabRole`.

## Arquitectura y flujo de datos

1. **Publicación (`POST /eventos` o invocación directa):** Se envía un evento con `device_id` a la función `iot_publisher_lambda`, que genera la lectura y guarda un archivo JSON en el bucket S3 `iot-eventos-<ACCOUNT_ID>` bajo `events/<device_id>/<uuid>.json`.
2. **Ingesta asíncrona:** El evento en S3 dispara `iot_ingestor_lambda`, que lee el objeto y almacena el registro en la tabla DynamoDB `iot_lecturas`.
3. **Consulta (`GET /sensores/{sensor_id}`):** La API en Chalice consulta `iot_lecturas` por `device_id` (con soporte opcional de `limit`), convierte los valores `Decimal` de DynamoDB a `int`/`float` y devuelve la respuesta en JSON.

## Estructura del proyecto

```text
.
├── Makefile
├── README.md
├── ToDo.md
├── api/
│   ├── app.py
│   └── .chalice/
│       └── config.json
├── infraestructura/
├── lambdas/
│   ├── deploy.sh
│   ├── requirements.txt
│   └── src/
│       ├── ingestor/
│       └── publisher/
│           └── lambda_function.py
├── venv/
└── venv-api/

## Comandos para probar POST y GET
```
Reemplaza `https://y6jm23uqc3.execute-api.us-east-1.amazonaws.com/api` por la URL de tu API. Esta se obtiene con el comando
```bash 
chalice url
```


### Probar POST `/eventos`

```bash
# 1. Envío válido (esperado: HTTP 200)
curl -i -w "\n" -X POST "https://y6jm23uqc3.execute-api.us-east-1.amazonaws.com/api/eventos" \
  -H "Content-Type: application/json" \
  -d '{"device_id": "sensor-02"}'

# 2. Sin device_id (esperado: HTTP 400)
curl -i -w "\n" -X POST "https://y6jm23uqc3.execute-api.us-east-1.amazonaws.com/api/eventos" \
  -H "Content-Type: application/json" \
  -d '{}'

# 3. JSON mal formado (esperado: HTTP 400)
curl -i -w "\n" -X POST "https://y6jm23uqc3.execute-api.us-east-1.amazonaws.com/api/eventos" \
  -H "Content-Type: application/json" \
  -d '{no-es-json}'
```


### Probar Get 
```bash
# 1. Consultar todas las lecturas de un sensor (esperado: HTTP 200)
curl -i -w "\n" -X GET "https://y6jm23uqc3.execute-api.us-east-1.amazonaws.com/api/sensores/sensor-02"

# 2. Consultar con límite válido (esperado: HTTP 200)
curl -i -w "\n" -X GET "https://y6jm23uqc3.execute-api.us-east-1.amazonaws.com/api/sensores/sensor-02?limit=1"

# 3. Consultar con límite inválido (esperado: HTTP 400)
curl -i -w "\n" -X GET "https://y6jm23uqc3.execute-api.us-east-1.amazonaws.com/api/sensores/sensor-02?limit=0"