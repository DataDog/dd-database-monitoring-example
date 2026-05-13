package main

import (
	"context"
	"database/sql"
	"log"
	"math/rand"
	"time"
)

type querySet struct {
	simpleSelect    string
	joinQuery       string
	insertOrder     string
	insertOrderPG   string // postgres uses RETURNING id
	insertItem      string
	updateStatus    string
	fullTableScan   string
	selectForUpdate string
	updateLocked    string
	randomOrderID   string
}

func buildQuerySet(driver string) querySet {
	if driver == "postgres" {
		return querySet{
			simpleSelect: `SELECT id, name, email, created_at FROM users WHERE id = $1`,
			joinQuery: `SELECT u.name, u.email,
				COUNT(o.id) AS order_count,
				COALESCE(SUM(o.total), 0) AS lifetime_value
			FROM users u
			LEFT JOIN orders o ON o.user_id = u.id
			WHERE u.id = $1
			GROUP BY u.id, u.name, u.email`,
			insertOrderPG:   `INSERT INTO orders (user_id, status, total) VALUES ($1, 'pending', $2) RETURNING id`,
			insertItem:      `INSERT INTO order_items (order_id, product_id, quantity, price) VALUES ($1, $2, $3, $4)`,
			updateStatus:    `UPDATE orders SET status = $1, updated_at = NOW() WHERE id = $2`,
			fullTableScan:   `SELECT id, user_id, total, created_at FROM orders WHERE status = $1 ORDER BY created_at DESC LIMIT 50`,
			selectForUpdate: `SELECT id, status FROM orders WHERE id = $1 FOR UPDATE`,
			updateLocked:    `UPDATE orders SET status = $1, updated_at = NOW() WHERE id = $2`,
			randomOrderID:   `SELECT id FROM orders ORDER BY RANDOM() LIMIT 1`,
		}
	}
	return querySet{
		simpleSelect: `SELECT id, name, email, created_at FROM users WHERE id = ?`,
		joinQuery: `SELECT u.name, u.email,
			COUNT(o.id) AS order_count,
			COALESCE(SUM(o.total), 0) AS lifetime_value
		FROM users u
		LEFT JOIN orders o ON o.user_id = u.id
		WHERE u.id = ?
		GROUP BY u.id, u.name, u.email`,
		insertOrder:     `INSERT INTO orders (user_id, status, total) VALUES (?, 'pending', ?)`,
		insertItem:      `INSERT INTO order_items (order_id, product_id, quantity, price) VALUES (?, ?, ?, ?)`,
		updateStatus:    `UPDATE orders SET status = ?, updated_at = NOW() WHERE id = ?`,
		fullTableScan:   `SELECT id, user_id, total, created_at FROM orders WHERE status = ? ORDER BY created_at DESC LIMIT 50`,
		selectForUpdate: `SELECT id, status FROM orders WHERE id = ? FOR UPDATE`,
		updateLocked:    `UPDATE orders SET status = ?, updated_at = NOW() WHERE id = ?`,
		randomOrderID:   `SELECT id FROM orders ORDER BY RAND() LIMIT 1`,
	}
}

func runWorkload(ctx context.Context, db *sql.DB, cfg Config) {
	q := buildQuerySet(cfg.Driver)

	go loopSimpleSelect(ctx, db, q)
	go loopJoinQuery(ctx, db, q)
	go loopInsertOrder(ctx, db, q, cfg.Driver)
	go loopUpdateStatus(ctx, db, q)
	go loopFullTableScan(ctx, db, q)
	// Two goroutines offset by 300ms compete for the same rows, creating lock waits.
	go loopBlockingQuery(ctx, db, q)
	go func() {
		time.Sleep(300 * time.Millisecond)
		loopBlockingQuery(ctx, db, q)
	}()
}

func loopSimpleSelect(ctx context.Context, db *sql.DB, q querySet) {
	for {
		if ctx.Err() != nil {
			return
		}
		userID := rand.Intn(50) + 1
		var id int
		var name, email string
		var createdAt time.Time
		row := db.QueryRowContext(ctx, q.simpleSelect, userID)
		if err := row.Scan(&id, &name, &email, &createdAt); err != nil && err != sql.ErrNoRows {
			log.Printf("simpleSelect: %v", err)
		}
		jitter(50, 150)
	}
}

func loopJoinQuery(ctx context.Context, db *sql.DB, q querySet) {
	for {
		if ctx.Err() != nil {
			return
		}
		userID := rand.Intn(50) + 1
		var name, email string
		var orderCount int
		var lifetimeValue float64
		row := db.QueryRowContext(ctx, q.joinQuery, userID)
		if err := row.Scan(&name, &email, &orderCount, &lifetimeValue); err != nil && err != sql.ErrNoRows {
			log.Printf("joinQuery: %v", err)
		}
		jitter(100, 300)
	}
}

func loopInsertOrder(ctx context.Context, db *sql.DB, q querySet, driver string) {
	for {
		if ctx.Err() != nil {
			return
		}
		userID := rand.Intn(50) + 1
		total := float64(rand.Intn(800)+50) + 0.99

		tx, err := db.BeginTx(ctx, nil)
		if err != nil {
			jitter(500, 1000)
			continue
		}

		var orderID int64
		if driver == "postgres" {
			err = tx.QueryRowContext(ctx, q.insertOrderPG, userID, total).Scan(&orderID)
		} else {
			var res sql.Result
			res, err = tx.ExecContext(ctx, q.insertOrder, userID, total)
			if err == nil {
				orderID, err = res.LastInsertId()
			}
		}
		if err != nil {
			tx.Rollback()
			jitter(500, 1000)
			continue
		}

		numItems := rand.Intn(3) + 1
		for i := 0; i < numItems; i++ {
			productID := rand.Intn(len(products)) + 1
			quantity := rand.Intn(4) + 1
			price := products[productID-1].price
			if _, err = tx.ExecContext(ctx, q.insertItem, orderID, productID, quantity, price); err != nil {
				break
			}
		}
		if err != nil {
			tx.Rollback()
		} else {
			tx.Commit()
		}
		jitter(200, 500)
	}
}

func loopUpdateStatus(ctx context.Context, db *sql.DB, q querySet) {
	for {
		if ctx.Err() != nil {
			return
		}
		var orderID int
		if err := db.QueryRowContext(ctx, q.randomOrderID).Scan(&orderID); err != nil {
			jitter(200, 500)
			continue
		}
		newStatus := statuses[rand.Intn(len(statuses))]
		if _, err := db.ExecContext(ctx, q.updateStatus, newStatus, orderID); err != nil {
			log.Printf("updateStatus: %v", err)
		}
		jitter(100, 250)
	}
}

func loopFullTableScan(ctx context.Context, db *sql.DB, q querySet) {
	for {
		if ctx.Err() != nil {
			return
		}
		// Queries orders by status with no index — produces seq scans visible in DBM
		status := statuses[rand.Intn(len(statuses))]
		rows, err := db.QueryContext(ctx, q.fullTableScan, status)
		if err != nil {
			log.Printf("fullTableScan: %v", err)
			jitter(500, 1000)
			continue
		}
		for rows.Next() {
		}
		rows.Close()
		jitter(400, 900)
	}
}

func loopBlockingQuery(ctx context.Context, db *sql.DB, q querySet) {
	// Targets a small pool of order IDs so the two blocking goroutines collide often.
	contestedIDs := []int{1, 2, 3, 4, 5}
	for {
		if ctx.Err() != nil {
			return
		}
		orderID := contestedIDs[rand.Intn(len(contestedIDs))]

		tx, err := db.BeginTx(ctx, nil)
		if err != nil {
			jitter(500, 1000)
			continue
		}

		var id int
		var status string
		err = tx.QueryRowContext(ctx, q.selectForUpdate, orderID).Scan(&id, &status)
		if err != nil {
			tx.Rollback()
			jitter(200, 500)
			continue
		}

		// Hold the lock long enough for the peer goroutine to block on it.
		time.Sleep(time.Duration(rand.Intn(400)+300) * time.Millisecond)

		newStatus := statuses[rand.Intn(len(statuses))]
		tx.ExecContext(ctx, q.updateLocked, newStatus, id)
		tx.Commit()

		jitter(800, 1500)
	}
}

func jitter(minMs, maxMs int) {
	time.Sleep(time.Duration(rand.Intn(maxMs-minMs)+minMs) * time.Millisecond)
}
