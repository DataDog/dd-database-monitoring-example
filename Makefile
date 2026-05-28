.PHONY: mysql
mysql: check-apikey
	docker-compose -p dd-dbm-mysql -f docker-compose-mysql.yaml up --build agent app

.PHONY: postgres
postgres: check-apikey
	docker-compose -p dd-dbm-postgres -f docker-compose-postgres.yaml up --build agent app

.PHONY: clean
clean:
	docker-compose -p dd-dbm-postgres -f docker-compose-postgres.yaml down --rmi local
	docker-compose -p dd-dbm-mysql -f docker-compose-mysql.yaml down --rmi local
	docker-compose -p dd-dbm-postgres -f docker-compose-postgres.yaml rm -f
	docker-compose -p dd-dbm-mysql -f docker-compose-mysql.yaml rm -f

.PHONY: check-apikey
check-apikey:
ifndef DD_API_KEY
	$(error Please set your Datadog API key using `export DD_API_KEY=replace_your_key_here`)
endif
