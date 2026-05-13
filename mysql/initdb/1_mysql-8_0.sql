CREATE USER 'datadog'@'%' IDENTIFIED WITH mysql_native_password BY 'dog' WITH MAX_USER_CONNECTIONS 0;
GRANT REPLICATION CLIENT ON *.* TO 'datadog'@'%';
GRANT PROCESS ON *.* TO 'datadog'@'%';

CREATE SCHEMA orders;
CREATE USER 'orders'@'%' IDENTIFIED WITH mysql_native_password BY 'ordersPw';
GRANT ALL PRIVILEGES ON orders.* TO 'orders'@'%';
