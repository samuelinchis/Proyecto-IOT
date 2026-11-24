from chalice import BadRequestError, Chalice, Response
import boto3
import os
import json
from boto3.dynamodb.conditions import Key
from decimal import Decimal

app = Chalice(app_name='api')

lambda_client = boto3.client("lambda")

@app.route('/')
def index():
    return {'hello': 'world'}


@app.route('/eventos', methods=['POST'])
def temp_registry():

    #Guarda en JSON del cliente en la variable y revisa si
    #está mal formado para retornar un mensaje de error 
    #personalizado.
    try:
        body_as_json = app.current_request.json_body 
    except BadRequestError:
        return Response(body={
            'invalid_format': 'Format is not JSON'
        }, status_code=400)

    #Revisa si el JSON viene en formato de diccionario, si
    #no retorna un mensaje de error.
    if not isinstance(body_as_json, dict):
        return Response(body={
            'invalid_format': 'Format is not JSON or is empty'
        }, status_code=400)

    #Revisa si el campo de 'device_id' no está en el JSON,
    #si el campo tiene valores False, 0, "" o None, en 
    #cualquiera de estos casos retorna un mensaje de error.       
    elif not body_as_json.get('device_id'):
        return Response(body={
            'idnotfound': 'Sensor has no device_id'
        }, status_code=400)
    # Todo válido: invocamos a la publisher y devolvemos su respuesta.
    else:
        response = lambda_client.invoke(
            FunctionName=os.environ["PUBLISHER_FUNCTION_NAME"],
            InvocationType="RequestResponse",
            Payload=json.dumps(body_as_json),
        )

        # Si la publisher falló, no reportamos éxito.
        if response.get("FunctionError"):
            return Response(body={
                'error': 'La lambda publisher falló',
                'detalle': response["Payload"].read().decode("utf-8"),
            }, status_code=502)

        # Payload: bytes -> str -> dict -> dict dentro de "body".
        payload_dict = json.loads(
            json.loads(response["Payload"].read().decode("utf-8"))["body"]
        )
        return Response(body=payload_dict, status_code=200)



#Bloque de lo correspondiente a la función get

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ.get("TABLE_NAME", "iot_lecturas")
table = dynamodb.Table(TABLE_NAME)

def _convert_decimals(value):
    if isinstance(value, list):
        return [_convert_decimals(item) for item in value]
    if isinstance(value, dict):
        return {k: _convert_decimals(v) for k, v in value.items()}
    if isinstance(value, Decimal):
        return int(value) if value % 1 == 0 else float(value)
    return value

@app.route("/sensores/{sensor_id}", methods=["GET"])
def get_sensor_readings(sensor_id: str):
    query_params = app.current_request.query_params or {}
    query_kwargs = {
        "KeyConditionExpression": Key("device_id").eq(sensor_id),
    }

    if "limit" in query_params:
        try:
            limit_val = int(query_params["limit"])
            if limit_val <= 0:
                raise ValueError()
            query_kwargs["Limit"] = limit_val
        except ValueError:
            raise BadRequestError("El parámetro 'limit' debe ser un entero positivo.")

    response = table.query(**query_kwargs)
    items = _convert_decimals(response.get("Items", []))

    return {
        "sensor_id": sensor_id,
        "count": len(items),
        "lecturas": items,
    }
