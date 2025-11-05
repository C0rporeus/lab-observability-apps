use opentelemetry::KeyValue;
use opentelemetry_sdk::logs::{LoggerProvider, BatchLogProcessor};
use opentelemetry_sdk::Resource;
use opentelemetry_semantic_conventions::resource::SERVICE_NAME;
use opentelemetry_otlp::WithExportConfig;

pub fn init_logging() -> Result<LoggerProvider, Box<dyn std::error::Error>> {
    // Try to create OTLP exporter for logs
    // Note: opentelemetry_otlp 0.25.0 might not have full HTTP log exporter support
    // We'll use tonic (gRPC) which should work
    let endpoint = std::env::var("OTEL_EXPORTER_OTLP_ENDPOINT")
        .unwrap_or_else(|_| "http://otel-collector:4317".to_string());
    
    // Extract host:port from endpoint URL
    let endpoint_url = endpoint.trim_start_matches("http://").trim_start_matches("https://");
    let endpoint_clean = endpoint_url.split('/').next().unwrap_or("otel-collector:4317");
    
    let exporter = match opentelemetry_otlp::new_exporter()
        .tonic()
        .with_endpoint(endpoint_clean)
        .build_log_exporter() {
        Ok(exporter) => {
            println!("Successfully created OTLP log exporter for endpoint: {}", endpoint_clean);
            Some(exporter)
        },
        Err(e) => {
            eprintln!("Warning: Failed to create OTLP log exporter: {:?}, using no-op provider", e);
            None
        }
    };

    let mut builder = LoggerProvider::builder()
        .with_resource(Resource::new(vec![KeyValue::new(SERVICE_NAME, "micro-1")]));
    
    if let Some(exporter) = exporter {
        builder = builder.with_log_processor(
            BatchLogProcessor::builder(exporter, opentelemetry_sdk::runtime::Tokio)
                .build()
        );
    }
    
    let logger_provider = builder.build();
    
    Ok(logger_provider)
}
