CREATE USER 'datadog'@'%' IDENTIFIED BY 'dog';
GRANT REPLICATION CLIENT ON *.* TO 'datadog'@'%' WITH MAX_USER_CONNECTIONS 0;
GRANT PROCESS ON *.* TO 'datadog'@'%';

CREATE SCHEMA orders;
CREATE USER 'orders'@'%' IDENTIFIED BY 'ordersPw';
GRANT ALL PRIVILEGES ON orders.* TO 'orders'@'%';
