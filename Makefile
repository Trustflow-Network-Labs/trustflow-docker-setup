setup:
	git clone git@github.com:adgsm/trustflow-node ../trustflow-node
	cp -a ../trustflow-node/.env.example ../trustflow-node/.env
	cp -a ../trustflow-node/database/configs.example ../trustflow-node/database/configs
	cp -a ../trustflow-node/keystore/configs.example ../trustflow-node/keystore/configs
	cp -a ../trustflow-node/tfnode/configs.example ../trustflow-node/tfnode/configs
	cp -a ../trustflow-node/utils/configs.example ../trustflow-node/utils/configs
	mkdir ../trustflow-node/logs

start:
	docker compose up

stop:
	docker compose stop
