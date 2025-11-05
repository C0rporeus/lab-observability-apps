package db

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"micro-2/config"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"

	_ "github.com/lib/pq"
)

type WeatherRecord struct {
	ID          int32
	City        string
	Temperature float64
	Condition   string
	Humidity    *int32
	WindSpeed   *float64
	Timestamp   time.Time
}

type Database struct {
	db *sql.DB
}

func NewDatabase(host, port, user, password, dbname string) (*Database, error) {
	tracer := config.DBTracerProvider.Tracer("postgres")
	ctx := context.Background()
	ctx, span := tracer.Start(ctx, "postgres.connect",
		trace.WithAttributes(
			attribute.String("db.name", dbname),
			attribute.String("db.user", user),
			attribute.String("server.address", host),
			attribute.String("server.port", port),
		),
	)
	defer span.End()

	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		host, port, user, password, dbname)

	db, err := sql.Open("postgres", connStr)
	if err != nil {
		span.SetStatus(codes.Error, err.Error())
		span.RecordError(err)
		return nil, err
	}

	if err := db.Ping(); err != nil {
		span.SetStatus(codes.Error, err.Error())
		span.RecordError(err)
		return nil, err
	}

	span.SetStatus(codes.Ok, "Database connected successfully")

	return &Database{db: db}, nil
}

func (d *Database) SaveWeatherData(ctx context.Context, city string, temp float64, condition string, humidity int32, windSpeed float64) (int32, error) {
	tracer := config.DBTracerProvider.Tracer("postgres")
	ctx, span := tracer.Start(ctx, "postgres.query.execute",
		trace.WithAttributes(
			attribute.String("db.name", "observability"),
			attribute.String("db.operation", "INSERT"),
			attribute.String("db.statement", "INSERT INTO weather_data (city, temperature, \"condition\", humidity, wind_speed) VALUES ($1, $2, $3, $4, $5) RETURNING id"),
		),
	)
	defer span.End()

	query := `INSERT INTO weather_data (city, temperature, "condition", humidity, wind_speed) VALUES ($1, $2, $3, $4, $5) RETURNING id`

	var id int32
	err := d.db.QueryRowContext(ctx, query, city, temp, condition, humidity, windSpeed).Scan(&id)

	if err != nil {
		span.SetStatus(codes.Error, err.Error())
		span.RecordError(err)
		return 0, err
	}

	span.SetAttributes(attribute.Int("db.result.count", 1))
	span.SetStatus(codes.Ok, "Weather data saved successfully")

	return id, nil
}

func (d *Database) GetWeatherHistory(ctx context.Context, city string, limit int32) ([]WeatherRecord, error) {
	tracer := config.DBTracerProvider.Tracer("postgres")
	ctx, span := tracer.Start(ctx, "postgres.query.execute",
		trace.WithAttributes(
			attribute.String("db.name", "observability"),
			attribute.String("db.operation", "SELECT"),
		),
	)
	defer span.End()

	var rows *sql.Rows
	var err error

	if city != "" {
		span.SetAttributes(attribute.String("db.statement", "SELECT id, city, temperature, \"condition\", humidity, wind_speed, timestamp FROM weather_data WHERE city = $1 ORDER BY timestamp DESC LIMIT $2"))
		query := `SELECT id, city, temperature, "condition", humidity, wind_speed, timestamp FROM weather_data WHERE city = $1 ORDER BY timestamp DESC LIMIT $2`
		rows, err = d.db.QueryContext(ctx, query, city, limit)
	} else {
		span.SetAttributes(attribute.String("db.statement", "SELECT id, city, temperature, \"condition\", humidity, wind_speed, timestamp FROM weather_data ORDER BY timestamp DESC LIMIT $1"))
		query := `SELECT id, city, temperature, "condition", humidity, wind_speed, timestamp FROM weather_data ORDER BY timestamp DESC LIMIT $1`
		rows, err = d.db.QueryContext(ctx, query, limit)
	}

	if err != nil {
		span.SetStatus(codes.Error, err.Error())
		span.RecordError(err)
		return nil, err
	}
	defer rows.Close()

	var records []WeatherRecord
	for rows.Next() {
		var record WeatherRecord
		var humidity sql.NullInt32
		var windSpeed sql.NullFloat64

		err := rows.Scan(&record.ID, &record.City, &record.Temperature, &record.Condition, &humidity, &windSpeed, &record.Timestamp)
		if err != nil {
			span.RecordError(err)
			continue
		}

		if humidity.Valid {
			record.Humidity = &humidity.Int32
		}
		if windSpeed.Valid {
			record.WindSpeed = &windSpeed.Float64
		}

		records = append(records, record)
	}

	span.SetAttributes(attribute.Int("db.result.count", len(records)))
	span.SetStatus(codes.Ok, fmt.Sprintf("Retrieved %d records", len(records)))

	return records, nil
}

func (d *Database) Close() error {
	return d.db.Close()
}
