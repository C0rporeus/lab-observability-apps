use log::info;
use micro_1::config;
use micro_1::observability;
use micro_1::GreeterServiceImpl;
use micro_1::helloworld::greeter_server::GreeterServer;
use opentelemetry::trace::Tracer;
use tonic::transport::Server;
use tracing_subscriber::prelude::*;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    observability::init_observability()?;
    
    let logger_provider = match config::init_logging() {
        Ok(lp) => {
            println!("LoggerProvider initialized successfully");
            lp
        },
        Err(e) => {
            eprintln!("Warning: Failed to initialize logging: {}, continuing without log exporter", e);
            opentelemetry_sdk::logs::LoggerProvider::builder().build()
        }
    };
    
    let telemetry_layer = tracing_opentelemetry::OpenTelemetryLayer::default();
    
    let otel_log_layer = opentelemetry_appender_tracing::layer::OpenTelemetryTracingBridge::new(&logger_provider);
    
    match tracing_subscriber::Registry::default()
        .with(telemetry_layer)
        .with(otel_log_layer)
        .with(tracing_subscriber::fmt::layer()
            .with_ansi(false)
            .with_span_events(tracing_subscriber::fmt::format::FmtSpan::CLOSE)
            .json()
            .with_writer(std::io::stdout))
        .with(tracing_subscriber::EnvFilter::from_default_env())
        .try_init() {
        Ok(_) => println!("Tracing subscriber initialized successfully with OpenTelemetry layer and log bridge"),
        Err(_) => {
            println!("Warning: Could not initialize tracing subscriber, but continuing...");
        }
    }

    let tracer = opentelemetry::global::tracer("micro-1");
    let _span = tracer.start("server-startup");

    info!("Starting gRPC server...");

    let addr = "[::0]:50051".parse()?;
    let greeter = match GreeterServiceImpl::new().await {
        Ok(g) => g,
        Err(e) => {
            eprintln!("Failed to initialize GreeterServiceImpl: {}", e);
            return Err(format!("Failed to initialize service: {}", e).into());
        }
    };

    info!("gRPC server listening on {}", addr);

    Server::builder()
        .add_service(GreeterServer::new(greeter))
        .serve(addr)
        .await?;

    opentelemetry::global::shutdown_tracer_provider();
    logger_provider.shutdown();

    Ok(())
}
