from chalice import BadRequestError, Chalice, Response

app = Chalice(app_name='api')


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
    #Retorna que todo está bien (código 200) si no cayó en 
    #una excepción
    else:
        return Response(body={'mensaje':'Correcto'},
                        status_code=200)


