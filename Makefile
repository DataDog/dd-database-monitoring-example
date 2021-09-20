.PHONY: mysql
mysql: check-apikey
	docker-compose -f docker-compose-mysql.yaml up agent sysbench

.PHONY: postgres
postgres: check-apikey
	docker-compose -f docker-compose-postgres.yaml up agent pgbench

.PHONY: clean
clean:
	docker-compose down
	docker-compose rm -f

.PHONY: check-apikey
check-apikey:
ifndef DD_API_KEY
	$(error Please set your Datadog API key using `export DD_API_KEY=replace_your_key_here`)
endif