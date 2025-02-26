use log::{error, Level};
use opentelemetry::KeyValue;
use opentelemetry_appender_log::OpenTelemetryLogBridge;
use opentelemetry_sdk::logs::LoggerProvider;
use opentelemetry_sdk::Resource;
use opentelemetry_semantic_conventions::resource::SERVICE_NAME;
use opentelemetry_stdout;

fn main() {
    let exporter = opentelemetry_stdout::LogExporter::default();
    
    let logger_provider = LoggerProvider::builder()
        .with_resource(Resource::new(vec![KeyValue::new(SERVICE_NAME, "micro-1")]))
        .with_simple_exporter(exporter)
        .build();

    let otel_log_appender = OpenTelemetryLogBridge::new(&logger_provider);
    log::set_boxed_logger(Box::new(otel_log_appender)).unwrap();
    log::set_max_level(Level::Error.to_level_filter());

    error!(target: "my-target", "hello from {}. My price is {}", "apple", 2.99);
}