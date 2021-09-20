GRANT SELECT ON performance_schema.* TO 'datadog'@'%';
GRANT CREATE TEMPORARY TABLES ON `datadog`.* TO 'datadog'@'%';

CREATE SCHEMA datadog;

DELIMITER $$

CREATE PROCEDURE datadog.explain_statement(IN query TEXT)
    SQL SECURITY DEFINER
BEGIN
    SET @explain := CONCAT('EXPLAIN FORMAT=json ', query);
    PREPARE stmt FROM @explain;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END $$

-- (Optional) Gives the agent the ability to enable performance schema events_statements consumers on databases where they can't be enabled permanently in the configuration (like RDS Aurora)
CREATE PROCEDURE datadog.enable_events_statements_consumers()
    SQL SECURITY DEFINER
BEGIN
    UPDATE performance_schema.setup_consumers SET enabled='YES' WHERE name LIKE 'events_statements_%';
END $$

DELIMITER ;

GRANT EXECUTE ON PROCEDURE datadog.explain_statement TO 'datadog'@'%';
GRANT EXECUTE ON PROCEDURE datadog.enable_events_statements_consumers TO 'datadog'@'%';

-- DBM additional setup
CREATE SCHEMA sbtest;

DELIMITER $$

CREATE PROCEDURE sbtest.explain_statement(IN query TEXT)
    SQL SECURITY DEFINER
BEGIN
    SET @explain := CONCAT('EXPLAIN FORMAT=json ', query);
    PREPARE stmt FROM @explain;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END $$

DELIMITER ;

GRANT EXECUTE ON PROCEDURE sbtest.explain_statement to 'datadog'@'%';
