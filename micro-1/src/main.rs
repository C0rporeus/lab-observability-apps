use log::{error, Level};
use opentelemetry::KeyValue;
use opentelemetry_appender_log::OpenTelemetryLogBridge;
use opentelemetry_sdk::logs::LoggerProvider;
use opentelemetry_sdk::Resource;
use opentelemetry_semantic_conventions::resource::SERVICE_NAME;
use opentelemetry_otlp as otlp;
use opentelemetry_otlp::WithExportConfig; // Import WithExportConfig trait - ADD THIS LINE
use opentelemetry_sdk::trace;
use tonic::{transport::ClientTlsConfig, Request, Status};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let grpc_exporter = otlp::new_exporter()
        .tonic()
        .with_endpoint("http://otel-collector:4317") // Endpoint CORRECTO: Servicio otel-collector y puerto gRPC
        .build_log_exporter()?;

    let logger_provider = LoggerProvider::builder()
        .with_resource(Resource::new(vec![KeyValue::new(SERVICE_NAME, "micro-1")]))
        .with_simple_exporter(grpc_exporter)
        .build();

    let otel_log_appender = OpenTelemetryLogBridge::new(&logger_provider);
    log::set_boxed_logger(Box::new(otel_log_appender)).unwrap();
    log::set_max_level(Level::Error.to_level_filter());

    error!(target: "my-target", "hello from {}. My price is {}", "apple", 2.99);

    opentelemetry::global::shutdown_tracer_provider();
    logger_provider.shutdown();

    Ok(())
}