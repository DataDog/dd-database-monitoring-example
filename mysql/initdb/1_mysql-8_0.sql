CREATE USER 'datadog'@'%' IDENTIFIED WITH mysql_native_password BY 'dog' WITH MAX_USER_CONNECTIONS 5;
GRANT REPLICATION CLIENT ON *.* TO 'datadog'@'%';
GRANT PROCESS ON *.* TO 'datadog'@'%';

CREATE SCHEMA sbtest;
CREATE USE 'sbtest'@'%' IDENTIFIED WITH mysql_native_password BY 'sbtestpw';
GRANT ALL PRIVILEGES ON sbtest.* TO 'sbtest'@'%';
