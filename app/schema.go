package main

import (
	"database/sql"
	"fmt"
	"log"
	"math/rand"
)

var postgresSchema = []string{
	`CREATE TABLE IF NOT EXISTS users (
		id SERIAL PRIMARY KEY,
		name TEXT NOT NULL,
		email TEXT NOT NULL,
		created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
	)`,
	`CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email)`,
	`CREATE TABLE IF NOT EXISTS products (
		id SERIAL PRIMARY KEY,
		name TEXT NOT NULL,
		price NUMERIC(10,2) NOT NULL,
		inventory INTEGER NOT NULL DEFAULT 100
	)`,
	`CREATE TABLE IF NOT EXISTS orders (
		id SERIAL PRIMARY KEY,
		user_id INTEGER NOT NULL,
		status TEXT NOT NULL DEFAULT 'pending',
		total NUMERIC(10,2) NOT NULL DEFAULT 0,
		created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
	)`,
	// Intentionally no index on status — triggers full table scans visible in DBM
	`CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id)`,
	`CREATE TABLE IF NOT EXISTS order_items (
		id SERIAL PRIMARY KEY,
		order_id INTEGER NOT NULL,
		product_id INTEGER NOT NULL,
		quantity INTEGER NOT NULL,
		price NUMERIC(10,2) NOT NULL
	)`,
	`CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id)`,
}

var mysqlSchema = []string{
	`CREATE TABLE IF NOT EXISTS users (
		id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
		name VARCHAR(100) NOT NULL,
		email VARCHAR(100) NOT NULL,
		created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		UNIQUE KEY idx_users_email (email)
	)`,
	`CREATE TABLE IF NOT EXISTS products (
		id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
		name VARCHAR(200) NOT NULL,
		price DECIMAL(10,2) NOT NULL,
		inventory INT NOT NULL DEFAULT 100
	)`,
	`CREATE TABLE IF NOT EXISTS orders (
		id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
		user_id INT NOT NULL,
		status VARCHAR(20) NOT NULL DEFAULT 'pending',
		total DECIMAL(10,2) NOT NULL DEFAULT 0,
		created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
		KEY idx_orders_user_id (user_id)
	)`,
	`CREATE TABLE IF NOT EXISTS order_items (
		id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
		order_id INT NOT NULL,
		product_id INT NOT NULL,
		quantity INT NOT NULL,
		price DECIMAL(10,2) NOT NULL,
		KEY idx_order_items_order_id (order_id)
	)`,
}

func setupSchema(db *sql.DB, driver string) error {
	stmts := postgresSchema
	if driver == "mysql" {
		stmts = mysqlSchema
	}
	for _, stmt := range stmts {
		if _, err := db.Exec(stmt); err != nil {
			return fmt.Errorf("exec DDL: %w", err)
		}
	}
	return nil
}

var userNames = []string{
	"Alice Johnson", "Bob Smith", "Carol White", "David Brown", "Eve Davis",
	"Frank Wilson", "Grace Lee", "Henry Taylor", "Iris Anderson", "Jack Thomas",
	"Kate Martinez", "Liam Jackson", "Mia Harris", "Noah Thompson", "Olivia Garcia",
	"Peter Robinson", "Quinn Lewis", "Rachel Walker", "Sam Hall", "Tara Young",
	"Umar Allen", "Vera King", "Will Wright", "Xena Scott", "Yara Green",
	"Zoe Baker", "Aaron Nelson", "Bella Carter", "Chris Mitchell", "Diana Perez",
	"Ethan Turner", "Fiona Phillips", "George Campbell", "Hannah Parker", "Ian Evans",
	"Julia Edwards", "Kevin Collins", "Laura Stewart", "Mike Sanchez", "Nancy Morris",
	"Oscar Rogers", "Penny Reed", "Quinn Cook", "Rachel Morgan", "Samuel Bell",
	"Teresa Murphy", "Uma Bailey", "Victor Rivera", "Wendy Cooper", "Xander Richardson",
}

var products = []struct {
	name  string
	price float64
}{
	{"Laptop Pro 15", 1299.99}, {"Wireless Mouse", 29.99}, {"Mechanical Keyboard", 89.99},
	{"USB-C Hub", 49.99}, {"Monitor 27inch", 399.99}, {"Webcam HD", 79.99},
	{"Noise Cancelling Headphones", 199.99}, {"External SSD 1TB", 129.99},
	{"Desk Lamp LED", 34.99}, {"Phone Stand", 19.99}, {"Tablet 10inch", 449.99},
	{"Smart Watch", 249.99}, {"Bluetooth Speaker", 59.99}, {"Microphone USB", 99.99},
	{"Graphics Card", 549.99}, {"RAM 32GB", 119.99}, {"CPU Cooler", 79.99},
	{"Desk Mat", 39.99}, {"Cable Management Kit", 24.99}, {"Power Strip Surge", 44.99},
}

var statuses = []string{"pending", "processing", "shipped", "delivered", "cancelled"}

func seedData(db *sql.DB, driver string) error {
	var count int
	if err := db.QueryRow("SELECT COUNT(*) FROM users").Scan(&count); err != nil {
		return err
	}
	if count > 0 {
		log.Printf("found %d existing users, skipping seed", count)
		return nil
	}

	ph := placeholderFn(driver)

	// Seed users
	insertUser := fmt.Sprintf("INSERT INTO users (name, email) VALUES (%s, %s)", ph(1), ph(2))
	for i, name := range userNames {
		email := fmt.Sprintf("user%d@example.com", i+1)
		if _, err := db.Exec(insertUser, name, email); err != nil {
			return fmt.Errorf("insert user: %w", err)
		}
	}
	log.Printf("seeded %d users", len(userNames))

	// Seed products
	insertProduct := fmt.Sprintf("INSERT INTO products (name, price, inventory) VALUES (%s, %s, %s)", ph(1), ph(2), ph(3))
	for _, p := range products {
		if _, err := db.Exec(insertProduct, p.name, p.price, rand.Intn(200)+50); err != nil {
			return fmt.Errorf("insert product: %w", err)
		}
	}
	log.Printf("seeded %d products", len(products))

	// Seed orders
	if err := seedOrders(db, driver, 500); err != nil {
		return fmt.Errorf("seed orders: %w", err)
	}
	log.Printf("seeded 500 orders")

	return nil
}

func seedOrders(db *sql.DB, driver string, n int) error {
	ph := placeholderFn(driver)
	insertOrder := fmt.Sprintf("INSERT INTO orders (user_id, status, total) VALUES (%s, %s, %s)", ph(1), ph(2), ph(3))
	insertItem := fmt.Sprintf("INSERT INTO order_items (order_id, product_id, quantity, price) VALUES (%s, %s, %s, %s)", ph(1), ph(2), ph(3), ph(4))

	for i := 0; i < n; i++ {
		userID := rand.Intn(len(userNames)) + 1
		status := statuses[rand.Intn(len(statuses))]
		total := float64(rand.Intn(1000)+50) + 0.99

		var orderID int64
		if driver == "postgres" {
			q := fmt.Sprintf("INSERT INTO orders (user_id, status, total) VALUES ($1, $2, $3) RETURNING id")
			if err := db.QueryRow(q, userID, status, total).Scan(&orderID); err != nil {
				return err
			}
		} else {
			res, err := db.Exec(insertOrder, userID, status, total)
			if err != nil {
				return err
			}
			orderID, err = res.LastInsertId()
			if err != nil {
				return err
			}
		}

		numItems := rand.Intn(3) + 1
		for j := 0; j < numItems; j++ {
			productID := rand.Intn(len(products)) + 1
			quantity := rand.Intn(4) + 1
			price := products[productID-1].price
			if _, err := db.Exec(insertItem, orderID, productID, quantity, price); err != nil {
				return err
			}
		}
	}
	return nil
}

// placeholderFn returns a function that generates $N (postgres) or ? (mysql) placeholders.
func placeholderFn(driver string) func(int) string {
	if driver == "postgres" {
		return func(n int) string { return fmt.Sprintf("$%d", n) }
	}
	return func(_ int) string { return "?" }
}
