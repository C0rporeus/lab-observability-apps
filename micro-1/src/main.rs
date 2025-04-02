use log::{info, Level};
use micro_1::helloworld::greeter_server::GreeterServer;
use micro_1::GreeterService;
use opentelemetry::trace::{Span, Tracer};
use opentelemetry::KeyValue;
use opentelemetry_appender_log::OpenTelemetryLogBridge;
use opentelemetry_sdk::logs::LoggerProvider;
use opentelemetry_sdk::Resource;
use opentelemetry_semantic_conventions::resource::SERVICE_NAME;
use opentelemetry_otlp::{self as otlp, WithExportConfig};
use tonic::transport::Server;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Configure OTLP exporter
    let grpc_exporter = otlp::new_exporter()
        .tonic()
        .with_endpoint("http://otel-collector:4317")
        .build_log_exporter()?;

    let logger_provider = LoggerProvider::builder()
        .with_resource(Resource::new(vec![KeyValue::new(SERVICE_NAME, "micro-1")]))
        .with_simple_exporter(grpc_exporter)
        .build();

    let otel_log_appender = OpenTelemetryLogBridge::new(&logger_provider);
    log::set_boxed_logger(Box::new(otel_log_appender))?;
    log::set_max_level(Level::Info.to_level_filter());

    // Initialize tracer
    let tracer = opentelemetry::global::tracer("micro-1");
    let _span = tracer.start("server-startup");

    info!("Starting gRPC server...");

    // Initialize gRPC server
    let addr = "[::0]:50051".parse()?;
    let greeter = GreeterService::default();

    info!("gRPC server listening on {}", addr);

    Server::builder()
        .add_service(GreeterServer::new(greeter))
        .serve(addr)
        .await?;

    opentelemetry::global::shutdown_tracer_provider();
    logger_provider.shutdown();

    Ok(())
}
