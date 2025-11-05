use opentelemetry::{global, trace::{Tracer, Span}, KeyValue, Context};
use serde::{Deserialize, Serialize};
use tokio_postgres::{NoTls, Client};
use std::sync::Arc;
use chrono::{DateTime, Utc};

#[derive(Debug, Clone)]
pub struct Database {
    client: Arc<Client>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct WeatherRecord {
    pub id: i32,
    pub city: String,
    pub temperature: f64,
    pub condition: String,
    pub humidity: Option<i32>,
    pub wind_speed: Option<f64>,
    pub timestamp: DateTime<Utc>,
}

impl Database {
    pub async fn new(host: &str, port: u16, user: &str, password: &str, dbname: &str) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let tracer = global::tracer("micro-1-db");
        let mut span = tracer.start("postgres.connect");
        span.set_attribute(KeyValue::new("db.system", "postgresql"));
        span.set_attribute(KeyValue::new("db.name", dbname.to_string()));
        span.set_attribute(KeyValue::new("db.user", user.to_string()));
        span.set_attribute(KeyValue::new("server.address", host.to_string()));
        span.set_attribute(KeyValue::new("server.port", port as i64));

        let connection_string = format!("host={} port={} user={} password={} dbname={}", host, port, user, password, dbname);
        
        let (client, connection) = tokio_postgres::connect(&connection_string, NoTls).await?;

        span.set_status(opentelemetry::trace::Status::Ok);
        span.end();

        tokio::spawn(async move {
            if let Err(e) = connection.await {
                eprintln!("PostgreSQL connection error: {}", e);
            }
        });

        Ok(Database {
            client: Arc::new(client),
        })
    }

    pub async fn save_weather_data(&self, ctx: &Context, city: &str, temp: f64, condition: &str, humidity: Option<i32>, wind_speed: Option<f64>) -> Result<i32, Box<dyn std::error::Error + Send + Sync>> {
        let tracer = global::tracer("micro-1-db");
        let mut span = tracer.start_with_context("postgres.query.execute", ctx);
        span.set_attribute(KeyValue::new("db.system", "postgresql"));
        span.set_attribute(KeyValue::new("db.name", "observability"));
        span.set_attribute(KeyValue::new("db.statement", "INSERT INTO weather_data (city, temperature, condition, humidity, wind_speed) VALUES ($1, $2, $3, $4, $5) RETURNING id"));
        span.set_attribute(KeyValue::new("db.operation", "INSERT"));
        span.set_attribute(KeyValue::new("weather.city", city.to_string()));
        span.set_attribute(KeyValue::new("weather.temperature", temp));

        let result = self.client
            .query_one(
                "INSERT INTO weather_data (city, temperature, \"condition\", humidity, wind_speed) VALUES ($1, $2, $3, $4, $5) RETURNING id",
                &[&city, &temp, &condition, &humidity, &wind_speed]
            )
            .await;

        match result {
            Ok(row) => {
                let id: i32 = row.get(0);
                span.set_attribute(KeyValue::new("db.result.count", 1));
                span.set_attribute(KeyValue::new("db.record.id", id as i64));
                span.set_status(opentelemetry::trace::Status::Ok);
                span.end();
                Ok(id)
            }
            Err(e) => {
                span.set_attribute(KeyValue::new("error", true));
                span.set_attribute(KeyValue::new("error.message", e.to_string()));
                span.set_status(opentelemetry::trace::Status::Error {
                    description: e.to_string().into(),
                });
                span.end();
                Err(Box::new(e))
            }
        }
    }

    pub async fn get_weather_history(&self, ctx: &Context, city: Option<&str>, limit: i64) -> Result<Vec<WeatherRecord>, Box<dyn std::error::Error + Send + Sync>> {
        let tracer = global::tracer("micro-1-db");
        let mut span = tracer.start_with_context("postgres.query.execute", ctx);
        span.set_attribute(KeyValue::new("db.system", "postgresql"));
        span.set_attribute(KeyValue::new("db.name", "observability"));
        span.set_attribute(KeyValue::new("db.operation", "SELECT"));

        let query = if let Some(c) = city {
            span.set_attribute(KeyValue::new("db.statement", "SELECT id, city, temperature, condition, humidity, wind_speed, timestamp FROM weather_data WHERE city = $1 ORDER BY timestamp DESC LIMIT $2"));
            span.set_attribute(KeyValue::new("weather.city", c.to_string()));
            self.client
                .query("SELECT id, city, temperature, \"condition\", humidity, wind_speed, timestamp FROM weather_data WHERE city = $1 ORDER BY timestamp DESC LIMIT $2", &[&c, &limit])
                .await
        } else {
            span.set_attribute(KeyValue::new("db.statement", "SELECT id, city, temperature, condition, humidity, wind_speed, timestamp FROM weather_data ORDER BY timestamp DESC LIMIT $1"));
            self.client
                .query("SELECT id, city, temperature, \"condition\", humidity, wind_speed, timestamp FROM weather_data ORDER BY timestamp DESC LIMIT $1", &[&limit])
                .await
        };

        match query {
            Ok(rows) => {
                let records: Vec<WeatherRecord> = rows.iter().map(|row| {
                    WeatherRecord {
                        id: row.get(0),
                        city: row.get(1),
                        temperature: row.get(2),
                        condition: row.get(3),
                        humidity: row.get(4),
                        wind_speed: row.get(5),
                        timestamp: row.get(6),
                    }
                }).collect();
                span.set_attribute(KeyValue::new("db.result.count", records.len() as i64));
                span.set_status(opentelemetry::trace::Status::Ok);
                span.end();
                Ok(records)
            }
            Err(e) => {
                span.set_attribute(KeyValue::new("error", true));
                span.set_attribute(KeyValue::new("error.message", e.to_string()));
                span.set_status(opentelemetry::trace::Status::Error {
                    description: e.to_string().into(),
                });
                span.end();
                Err(Box::new(e))
            }
        }
    }
}
