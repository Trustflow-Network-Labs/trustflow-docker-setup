containers-up:
	docker-compose up

containers-stop:
	docker-compose stop

reset-db:
	docker-compose up -d postgres
	sleep 20
	cd ../trustflow-database/ && cat 00*.sql 01*.sql 02*.sql 03*.sql 04*.sql 05*.sql > ../trustflow-docker-setup/docker/postgres/import/import.sql
	@make import-db

import-db:
	docker-compose exec -T postgres psql -d postgres -U postgres -f /import/import.sql

skeleton:
	git clone git@github.com:adgsm/trustflow-database ../trustflow-database
	git clone git@github.com:adgsm/trustflow-node ../trustflow-node
	cp -a ../trustflow-node/.env.example ../trustflow-node/.env
	cp -a ../trustflow-node/database/configs.example ../trustflow-node/database/configs
	cp -a ../trustflow-node/keystore/configs.example ../trustflow-node/keystore/configs
	cp -a ../trustflow-node/tfnode/configs.example ../trustflow-node/tfnode/configs
	cp -a ../trustflow-node/utils/configs.example ../trustflow-node/utils/configs
	mkdir ../trustflow-node/logs

setup:
	@make skeleton
	@make containers-up &
	sleep 20
	@make reset-db

start:
	@make containers-up &
	sleep 5
	cd ../trustflow-node && go run main.go &
	sleep 5
	lsof -ti :30609 > /tmp/trustflow-node.pid

stop:
	kill `cat /tmp/trustflow-node.pid` || true
	@make containers-stop
