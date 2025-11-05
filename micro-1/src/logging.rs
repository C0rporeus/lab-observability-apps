
pub fn log_to_otel(_logger_provider: &opentelemetry_sdk::logs::LoggerProvider, level: &str, message: &str, _metadata: Option<Vec<opentelemetry::KeyValue>>) {
    match level {
        "error" => tracing::error!("{}", message),
        "warn" => tracing::warn!("{}", message),
        _ => tracing::info!("{}", message),
    }
}
