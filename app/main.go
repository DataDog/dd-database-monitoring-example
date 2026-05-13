package main

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	mysqldrv "github.com/go-sql-driver/mysql"
	"github.com/jackc/pgx/v5/stdlib"
	sqltrace "gopkg.in/DataDog/dd-trace-go.v1/contrib/database/sql"
	"gopkg.in/DataDog/dd-trace-go.v1/ddtrace/tracer"
)

func main() {
	log.SetFlags(log.Ltime)
	cfg := loadConfig()

	tracer.Start(
		tracer.WithService(cfg.Service),
		tracer.WithEnv(cfg.Env),
		tracer.WithAgentAddr(cfg.AgentHost+":8126"),
		tracer.WithLogStartup(false),
	)
	defer tracer.Stop()

	db := openDB(cfg)
	defer db.Close()

	if err := waitForDB(db); err != nil {
		log.Fatalf("database not ready: %v", err)
	}
	log.Printf("connected to %s at %s:%s/%s", cfg.Driver, cfg.DBHost, cfg.DBPort, cfg.DBName)

	if err := setupSchema(db, cfg.Driver); err != nil {
		log.Fatalf("schema setup: %v", err)
	}
	log.Println("schema ready")

	if err := seedData(db, cfg.Driver); err != nil {
		log.Fatalf("seed data: %v", err)
	}
	log.Println("seed data ready — starting workload")

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	runWorkload(ctx, db, cfg)

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig
	log.Println("shutting down")
}

func openDB(cfg Config) *sql.DB {
	driverName := cfg.Driver
	switch cfg.Driver {
	case "postgres":
		sqltrace.Register("pgx", stdlib.GetDefaultDriver(),
			sqltrace.WithServiceName(cfg.DBServiceName),
			sqltrace.WithDBMPropagation(tracer.DBMPropagationModeFull),
		)
		driverName = "pgx"
	case "mysql":
		sqltrace.Register("mysql", &mysqldrv.MySQLDriver{},
			sqltrace.WithServiceName(cfg.DBServiceName),
			sqltrace.WithDBMPropagation(tracer.DBMPropagationModeFull),
		)
	default:
		log.Fatalf("unsupported driver: %s (use 'postgres' or 'mysql')", cfg.Driver)
	}

	db, err := sqltrace.Open(driverName, cfg.DSN)
	if err != nil {
		log.Fatalf("open db: %v", err)
	}
	db.SetMaxOpenConns(20)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)
	return db
}

func waitForDB(db *sql.DB) error {
	deadline := time.Now().Add(60 * time.Second)
	for time.Now().Before(deadline) {
		if err := db.Ping(); err == nil {
			return nil
		}
		time.Sleep(time.Second)
	}
	return fmt.Errorf("database not ready after 60s")
}
