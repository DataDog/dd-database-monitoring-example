CREATE USER 'datadog'@'%' IDENTIFIED BY 'dog';
GRANT REPLICATION CLIENT ON *.* TO 'datadog'@'%' WITH MAX_USER_CONNECTIONS 0;
GRANT PROCESS ON *.* TO 'datadog'@'%';

CREATE SCHEMA sbtest;
CREATE USER 'sbtest'@'%' IDENTIFIED BY 'sbtestpw';
GRANT ALL PRIVILEGES ON sbtest.* TO 'sbtest'@'%';
