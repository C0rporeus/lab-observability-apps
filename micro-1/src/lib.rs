pub mod config;
pub mod observability;
pub mod service;
pub mod db;
pub mod weather;
pub mod logging;

pub mod helloworld {
    tonic::include_proto!("helloworld");
}

use helloworld::greeter_server::Greeter;
use helloworld::{HelloWorldRequest, HelloWorldResponse, MessageRequest, MessageResponse, 
    WeatherRequest, WeatherResponse, WeatherDataRequest, WeatherDataResponse,
    WeatherHistoryRequest, WeatherHistoryResponse, WeatherRecord};
use service::GreeterService;
use db::Database;
use weather::WeatherService;
use tracing::{info_span, Instrument};
use opentelemetry::{global, trace::{Tracer, Span}, KeyValue, Context};
use opentelemetry::propagation::Extractor;
use std::sync::Arc;

struct GrpcMetadataExtractor<'a> {
    metadata: &'a tonic::metadata::MetadataMap,
}

impl<'a> Extractor for GrpcMetadataExtractor<'a> {
    fn get(&self, key: &str) -> Option<&str> {
        self.metadata.get(key).and_then(|v| v.to_str().ok())
    }

    fn keys(&self) -> Vec<&str> {
        self.metadata
            .iter()
            .map(|kv| match kv {
                tonic::metadata::KeyAndValueRef::Ascii(k, _) => k.as_str(),
                tonic::metadata::KeyAndValueRef::Binary(k, _) => k.as_str(),
            })
            .collect()
    }
}

#[derive(Debug)]
pub struct GreeterServiceImpl {
    service: GreeterService,
    weather_service: Arc<WeatherService>,
    db: Arc<Database>,
}

impl GreeterServiceImpl {
    pub async fn new() -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        // Initialize database
        let db_host = std::env::var("DB_HOST").unwrap_or_else(|_| "postgres".to_string());
        let db_port = std::env::var("DB_PORT").unwrap_or_else(|_| "5432".to_string()).parse::<u16>().unwrap_or(5432);
        let db_user = std::env::var("DB_USER").unwrap_or_else(|_| "postgres".to_string());
        let db_password = std::env::var("DB_PASSWORD").unwrap_or_else(|_| "postgres123".to_string());
        let db_name = std::env::var("DB_NAME").unwrap_or_else(|_| "observability".to_string());
        
        let database = Database::new(&db_host, db_port, &db_user, &db_password, &db_name).await?;
        
        // Initialize weather service - la API key debe estar definida en variables de entorno
        let api_key = std::env::var("WEATHER_API_KEY")
            .map_err(|_| "WEATHER_API_KEY debe estar definida en variables de entorno")?;
        let weather_service = WeatherService::new(api_key);
        
        Ok(Self {
            service: GreeterService::new(),
            weather_service: Arc::new(weather_service),
            db: Arc::new(database),
        })
    }
}

#[tonic::async_trait]
impl Greeter for GreeterServiceImpl {
    async fn send_message(
        &self,
        request: tonic::Request<MessageRequest>,
    ) -> Result<tonic::Response<MessageResponse>, tonic::Status> {
        let start_time = std::time::Instant::now();
        let message = &request.get_ref().message;
        let span = info_span!("send_message", message = %message);
        
        let result = async {
            if message.is_empty() || message.len() > 1000 {
                tracing::warn!("Invalid message received: length={}", message.len());
                return Err(tonic::Status::invalid_argument("Invalid message length"));
            }
            
            match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                self.service.send_message(request.get_ref())
            })) {
                Ok(response) => {
                    tracing::info!("Message processed successfully: length={}", message.len());
                    Ok(tonic::Response::new(response))
                }
                Err(_) => {
                    tracing::error!("Panic occurred while processing message");
                    Err(tonic::Status::internal("Internal server error"))
                }
            }
        }
        .instrument(span)
        .await;
        
        let duration = start_time.elapsed().as_secs_f64();
        self.service.metrics.record_request_duration(duration, "send_message");
        
        if let Err(ref status) = result {
            tracing::error!("send_message failed: {}", status);
        }
        
        result
    }

    async fn get_hello_world(
        &self,
        request: tonic::Request<HelloWorldRequest>,
    ) -> Result<tonic::Response<HelloWorldResponse>, tonic::Status> {
        let start_time = std::time::Instant::now();
        
        let metadata = request.metadata();
        let extractor = GrpcMetadataExtractor { metadata };
        let parent_context = global::get_text_map_propagator(|propagator| propagator.extract(&extractor));
        
        // Create OpenTelemetry span using parent context
        let tracer = global::tracer("micro-1");
        let mut span = tracer.start_with_context("micro-1: get_hello_world", &parent_context);
        
        // Add RPC and service attributes
        span.set_attribute(KeyValue::new("rpc.system", "grpc"));
        span.set_attribute(KeyValue::new("rpc.service", "helloworld.Greeter"));
        span.set_attribute(KeyValue::new("rpc.method", "GetHelloWorld"));
        span.set_attribute(KeyValue::new("rpc.grpc.status_code", "0"));
        span.set_attribute(KeyValue::new("service.name", "micro-1"));
        span.set_attribute(KeyValue::new("service.version", "1.0.0"));
        span.set_attribute(KeyValue::new("service.language", "rust"));
        span.set_attribute(KeyValue::new("service.framework", "grpc"));
        
        // Add runtime attributes
        span.set_attribute(KeyValue::new("runtime.name", "rustc"));
        span.set_attribute(KeyValue::new("runtime.os", std::env::consts::OS));
        span.set_attribute(KeyValue::new("runtime.arch", std::env::consts::ARCH));
        
        // Add request attributes  
        span.set_attribute(KeyValue::new("request.timestamp", start_time.elapsed().as_nanos().to_string()));
        
        // Get trace_id and span_id to include in logs
        let span_context = span.span_context();
        let trace_id = span_context.trace_id().to_string();
        let span_id = span_context.span_id().to_string();
        
        let result = async {
            match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                self.service.get_hello_world()
            })) {
                Ok(response) => {
                    tracing::info!(trace_id = %trace_id, span_id = %span_id, "Hello world request processed successfully in micro-1");
                    Ok(tonic::Response::new(response))
                }
                Err(_) => {
                    tracing::error!(trace_id = %trace_id, span_id = %span_id, "Panic occurred while processing hello world request in micro-1");
                    Err(tonic::Status::internal("Internal server error"))
                }
            }
        }
        .await;
        
        // Get trace_id and span_id before ending span for error logging
        let span_context = span.span_context();
        let trace_id_final = span_context.trace_id().to_string();
        let span_id_final = span_context.span_id().to_string();
        
        let duration = start_time.elapsed();
        let duration_ms = duration.as_millis() as u64;
        let duration_secs = duration.as_secs_f64();
        
        // Add response attributes
        match &result {
            Ok(response) => {
                let response_greeting = response.get_ref().greeting.clone();
                span.set_attribute(KeyValue::new("response.message", response_greeting.clone()));
                span.set_attribute(KeyValue::new("response.success", true));
                span.set_attribute(KeyValue::new("response.message_length", response_greeting.len() as i64));
                span.set_status(opentelemetry::trace::Status::Ok);
            }
            Err(status) => {
                span.set_attribute(KeyValue::new("response.success", false));
                span.set_attribute(KeyValue::new("rpc.grpc.status_code", status.code().to_string()));
                span.set_attribute(KeyValue::new("error.message", status.message().to_string()));
                span.set_status(opentelemetry::trace::Status::Error {
                    description: status.message().to_string().into(),
                });
            }
        }
        
        span.set_attribute(KeyValue::new("response.duration_ms", duration_ms as i64));
        span.set_attribute(KeyValue::new("response.duration_seconds", duration_secs));
        
        span.end();
        
        let duration_f64 = duration.as_secs_f64();
        self.service.metrics.record_request_duration(duration_f64, "get_hello_world");
        
        if let Err(ref status) = result {
            tracing::error!(trace_id = %trace_id_final, span_id = %span_id_final, "get_hello_world failed: {}", status);
        }
        
        result
    }

    async fn get_weather(
        &self,
        request: tonic::Request<WeatherRequest>,
    ) -> Result<tonic::Response<WeatherResponse>, tonic::Status> {
        let start_time = std::time::Instant::now();
        let city = request.get_ref().city.clone();
        
        let metadata = request.metadata();
        let extractor = GrpcMetadataExtractor { metadata };
        let parent_context = global::get_text_map_propagator(|propagator| propagator.extract(&extractor));
        
        let tracer = global::tracer("micro-1");
        let mut span = tracer.start_with_context("micro-1: get_weather", &parent_context);
        
        span.set_attribute(KeyValue::new("rpc.system", "grpc"));
        span.set_attribute(KeyValue::new("rpc.service", "helloworld.Greeter"));
        span.set_attribute(KeyValue::new("rpc.method", "GetWeather"));
        span.set_attribute(KeyValue::new("weather.city", city.clone()));
        
        let span_context = span.span_context();
        let trace_id = span_context.trace_id().to_string();
        let span_id = span_context.span_id().to_string();
        
        // Pass parent_context to child spans - start_with_context will use it
        let child_context = parent_context.clone();
        
        // Get weather from API
        let weather_result = self.weather_service.get_weather(&child_context, &city).await;
        
        let duration = start_time.elapsed();
        span.set_attribute(KeyValue::new("response.duration_ms", duration.as_millis() as i64));
        
        match weather_result {
            Ok((temp, condition, humidity, wind_speed)) => {
                let response = WeatherResponse {
                    city: city.clone(),
                    temperature: temp,
                    condition,
                    humidity,
                    wind_speed,
                    source: "openweathermap".to_string(),
                };
                
                span.set_attribute(KeyValue::new("response.success", true));
                span.set_status(opentelemetry::trace::Status::Ok);
                span.end();
                
                tracing::info!(trace_id = %trace_id, span_id = %span_id, "Weather retrieved successfully for {}", city);
                Ok(tonic::Response::new(response))
            }
            Err(e) => {
                span.set_attribute(KeyValue::new("response.success", false));
                span.set_attribute(KeyValue::new("error.message", e.to_string()));
                span.set_status(opentelemetry::trace::Status::Error {
                    description: e.to_string().into(),
                });
                span.end();
                
                tracing::error!(trace_id = %trace_id, span_id = %span_id, "Failed to get weather for {}: {}", city, e);
                Err(tonic::Status::internal(format!("Failed to get weather: {}", e)))
            }
        }
    }

    async fn save_weather_data(
        &self,
        request: tonic::Request<WeatherDataRequest>,
    ) -> Result<tonic::Response<WeatherDataResponse>, tonic::Status> {
        let start_time = std::time::Instant::now();
        let data = request.get_ref();
        
        let metadata = request.metadata();
        let extractor = GrpcMetadataExtractor { metadata };
        let parent_context = global::get_text_map_propagator(|propagator| propagator.extract(&extractor));
        
        let tracer = global::tracer("micro-1");
        let mut span = tracer.start_with_context("micro-1: save_weather_data", &parent_context);
        
        span.set_attribute(KeyValue::new("rpc.system", "grpc"));
        span.set_attribute(KeyValue::new("rpc.service", "helloworld.Greeter"));
        span.set_attribute(KeyValue::new("rpc.method", "SaveWeatherData"));
        span.set_attribute(KeyValue::new("weather.city", data.city.clone()));
        span.set_attribute(KeyValue::new("weather.temperature", data.temperature));
        
        let span_context = span.span_context();
        let trace_id = span_context.trace_id().to_string();
        let span_id = span_context.span_id().to_string();
        
        // Pass parent_context to child spans
        let child_context = parent_context.clone();
        
        match self.db.save_weather_data(&child_context, &data.city, data.temperature, &data.condition, Some(data.humidity), Some(data.wind_speed)).await {
            Ok(id) => {
                let duration = start_time.elapsed();
                span.set_attribute(KeyValue::new("response.duration_ms", duration.as_millis() as i64));
                span.set_attribute(KeyValue::new("response.success", true));
                span.set_attribute(KeyValue::new("db.record.id", id as i64));
                span.set_status(opentelemetry::trace::Status::Ok);
                span.end();
                
                tracing::info!(trace_id = %trace_id, span_id = %span_id, "Weather data saved successfully with id {}", id);
                Ok(tonic::Response::new(WeatherDataResponse {
                    id,
                    message: "Weather data saved successfully".to_string(),
                }))
            }
            Err(e) => {
                span.set_attribute(KeyValue::new("response.success", false));
                span.set_attribute(KeyValue::new("error.message", e.to_string()));
                span.set_status(opentelemetry::trace::Status::Error {
                    description: e.to_string().into(),
                });
                span.end();
                
                tracing::error!(trace_id = %trace_id, span_id = %span_id, "Failed to save weather data: {}", e);
                Err(tonic::Status::internal(format!("Failed to save weather data: {}", e)))
            }
        }
    }

    async fn get_weather_history(
        &self,
        request: tonic::Request<WeatherHistoryRequest>,
    ) -> Result<tonic::Response<WeatherHistoryResponse>, tonic::Status> {
        let start_time = std::time::Instant::now();
        let req = request.get_ref();
        let city_filter = if req.city.is_empty() { None } else { Some(req.city.as_str()) };
        let limit = if req.limit <= 0 { 10 } else { req.limit as i64 };
        
        eprintln!("DEBUG: city_filter={:?}, limit={} (type i64)", city_filter, limit);
        
        let metadata = request.metadata();
        let extractor = GrpcMetadataExtractor { metadata };
        let parent_context = global::get_text_map_propagator(|propagator| propagator.extract(&extractor));
        
        let tracer = global::tracer("micro-1");
        let mut span = tracer.start_with_context("micro-1: get_weather_history", &parent_context);
        
        span.set_attribute(KeyValue::new("rpc.system", "grpc"));
        span.set_attribute(KeyValue::new("rpc.service", "helloworld.Greeter"));
        span.set_attribute(KeyValue::new("rpc.method", "GetWeatherHistory"));
        if let Some(city) = city_filter {
            span.set_attribute(KeyValue::new("weather.city", city.to_string()));
        }
        span.set_attribute(KeyValue::new("query.limit", limit));
        
        let span_context = span.span_context();
        let trace_id = span_context.trace_id().to_string();
        let span_id = span_context.span_id().to_string();
        
        let child_context = parent_context.clone();
        
        match self.db.get_weather_history(&child_context, city_filter, limit).await {
            Ok(records) => {
                let duration = start_time.elapsed();
                span.set_attribute(KeyValue::new("response.duration_ms", duration.as_millis() as i64));
                span.set_attribute(KeyValue::new("response.success", true));
                span.set_attribute(KeyValue::new("db.result.count", records.len() as i64));
                span.set_status(opentelemetry::trace::Status::Ok);
                span.end();
                
                let proto_records: Vec<WeatherRecord> = records.into_iter().map(|r| {
                    WeatherRecord {
                        id: r.id,
                        city: r.city,
                        temperature: r.temperature,
                        condition: r.condition,
                        humidity: r.humidity.unwrap_or(0),
                        wind_speed: r.wind_speed.unwrap_or(0.0),
                        timestamp: r.timestamp.to_rfc3339(),
                    }
                }).collect();
                
                let count = proto_records.len() as i32;
                let city_display = city_filter.unwrap_or("all cities").to_string();
                tracing::info!(trace_id = %trace_id, span_id = %span_id, "Retrieved {} weather records for {}", count, city_display);
                
                Ok(tonic::Response::new(WeatherHistoryResponse {
                    records: proto_records,
                    city: city_display,
                    count,
                }))
            }
            Err(e) => {
                span.set_attribute(KeyValue::new("response.success", false));
                span.set_attribute(KeyValue::new("error.message", e.to_string()));
                span.set_status(opentelemetry::trace::Status::Error {
                    description: e.to_string().into(),
                });
                span.end();
                
                tracing::error!(trace_id = %trace_id, span_id = %span_id, "Failed to get weather history: {}", e);
                Err(tonic::Status::internal(format!("Failed to get weather history: {}", e)))
            }
        }
    }
}

