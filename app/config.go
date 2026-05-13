package main

import (
	"fmt"
	"os"
)

type Config struct {
	Driver        string
	DBHost        string
	DBPort        string
	DBName        string
	AppUser       string
	AppPass       string
	DSN           string
	Service       string
	DBServiceName string
	Env           string
	AgentHost     string
}

func loadConfig() Config {
	driver := envOr("DB_DRIVER", "postgres")
	host := envOr("DB_HOST", "localhost")
	dbname := envOr("DB_NAME", "orders")
	user := envOr("APP_USER", "orders")
	pass := envOr("APP_PASSWORD", "ordersPw")

	defaultPort := "5432"
	if driver == "mysql" {
		defaultPort = "3306"
	}
	port := envOr("DB_PORT", defaultPort)

	return Config{
		Driver:        driver,
		DBHost:        host,
		DBPort:        port,
		DBName:        dbname,
		AppUser:       user,
		AppPass:       pass,
		DSN:           buildDSN(driver, host, port, dbname, user, pass),
		Service:       envOr("DD_SERVICE", "orders-app"),
		DBServiceName: envOr("DD_DATABASE_SERVICE", driver+"-orders"),
		Env:           envOr("DD_ENV", "development"),
		AgentHost:     envOr("DD_AGENT_HOST", "localhost"),
	}
}

func buildDSN(driver, host, port, dbname, user, pass string) string {
	if driver == "mysql" {
		return fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?parseTime=true", user, pass, host, port, dbname)
	}
	return fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=disable", user, pass, host, port, dbname)
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
