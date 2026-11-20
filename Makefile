# Makefile del ejemplo IoT: S3 -> Lambda -> DynamoDB
VENV   := venv
PY     := $(VENV)/bin/python
REQS   := lambdas/requirements.txt
VENV_API   := venv-api
REQS_API   := api/requirements.txt
INFRA  := infraestructura
REGION := us-east-1
DEVICE ?= sensor-01
# Para correr las lambdas en local contra AWS (bucket creado por Terraform)
LOCAL  := AWS_DEFAULT_REGION=$(REGION) BUCKET_NAME=$$(terraform -chdir=$(INFRA) output -raw bucket_name)

.PHONY: help venv api-venv test run-publisher run-ingestor infra-init infra-plan infra-apply infra-destroy deploy invoke clean

help:  ## Muestra esta ayuda
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-15s %s\n", $$1, $$2}'

venv: $(VENV)/bin/activate  ## Crea el virtualenv con lambdas/requirements.txt
$(VENV)/bin/activate: $(REQS)
	test -d $(VENV) || python3 -m venv $(VENV)
	$(VENV)/bin/pip install -Ur $(REQS)
	touch $(VENV)/bin/activate

api-venv: $(VENV_API)/bin/activate  ## Crea el virtualenv de la API con api/requirements.txt
$(VENV_API)/bin/activate: $(REQS_API)
	test -d $(VENV_API) || python3 -m venv $(VENV_API)
	$(VENV_API)/bin/pip install -Ur $(REQS_API)
	touch $(VENV_API)/bin/activate

test: venv  ## Prueba las lambdas localmente (moto, sin tocar AWS)
	$(PY) -m pytest -v lambdas/tests

run-publisher: venv  ## Corre la publisher en local contra AWS (DEVICE=sensor-01)
	$(LOCAL) $(PY) lambdas/src/publisher/lambda_function.py $(DEVICE)

run-ingestor: venv  ## Corre la ingestor en local contra AWS (KEY=events/...json)
	@test -n "$(KEY)" || { echo "Falta KEY. Ej: make run-ingestor KEY=events/sensor-01/<uuid>.json"; exit 1; }
	$(LOCAL) $(PY) lambdas/src/ingestor/lambda_function.py $(KEY)

infra-init:  ## terraform init
	cd $(INFRA) && terraform init

infra-plan: infra-init  ## terraform plan
	cd $(INFRA) && terraform plan -out=tfplan

infra-apply: infra-plan  ## terraform plan + apply
	cd $(INFRA) && terraform apply tfplan

infra-destroy:  ## Destruye la infraestructura
	cd $(INFRA) && terraform destroy

deploy:  ## Despliega el código de ambas lambdas (lambdas/deploy.sh)
	./lambdas/deploy.sh all

invoke:  ## Invoca la lambda publicadora en AWS (dispara todo el flujo)
	aws lambda invoke --function-name iot_publisher_lambda --region us-east-1 \
		--cli-binary-format raw-in-base64-out --payload '{"device_id":"sensor-01"}' /dev/stdout

clean:  ## Borra los virtualenv y caches
	rm -rf $(VENV) $(VENV_API) .pytest_cache lambdas/.pytest_cache
