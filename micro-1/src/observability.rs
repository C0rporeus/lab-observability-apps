use opentelemetry::{global, KeyValue};
use opentelemetry_sdk::{metrics::SdkMeterProvider, Resource, trace::TracerProvider as SdkTracerProvider, propagation::TraceContextPropagator};
use opentelemetry_semantic_conventions::resource::SERVICE_NAME;
use opentelemetry_otlp::{self as otlp, WithExportConfig};

#[derive(Debug)]
pub struct MetricsHandler {
    pub message_counter: opentelemetry::metrics::Counter<u64>,
    pub hello_world_counter: opentelemetry::metrics::Counter<u64>,
    pub request_duration: opentelemetry::metrics::Histogram<f64>,
}

impl MetricsHandler {
    pub fn new() -> Self {
        let meter = global::meter("micro-1");
        
        Self {
            message_counter: meter
                .u64_counter("messages_processed_total")
                .with_description("Total number of messages processed")
                .init(),
            hello_world_counter: meter
                .u64_counter("hello_world_requests_total")
                .with_description("Total number of hello world requests")
                .init(),
            request_duration: meter
                .f64_histogram("request_duration_seconds")
                .with_description("Request duration in seconds")
                .init(),
        }
    }

    pub fn record_message_processed(&self, endpoint: &str) {
        self.message_counter.add(1, &[KeyValue::new("endpoint", endpoint.to_string())]);
    }

    pub fn record_hello_world_request(&self, endpoint: &str) {
        self.hello_world_counter.add(1, &[KeyValue::new("endpoint", endpoint.to_string())]);
    }

    pub fn record_request_duration(&self, duration: f64, endpoint: &str) {
        self.request_duration.record(duration, &[KeyValue::new("endpoint", endpoint.to_string())]);
    }
}

pub fn init_observability() -> Result<(), Box<dyn std::error::Error>> {
    let service_name = std::env::var("OTEL_SERVICE_NAME")
        .unwrap_or_else(|_| "micro-1".to_string());
    
    let resource = Resource::new(vec![KeyValue::new(SERVICE_NAME, service_name.clone())]);
    
    let endpoint = std::env::var("OTEL_EXPORTER_OTLP_ENDPOINT")
        .unwrap_or_else(|_| "http://otel-collector:4317".to_string());
    
    println!("Initializing OpenTelemetry tracer with endpoint: {}", endpoint);
    
    let tracer_provider = match otlp::new_exporter()
        .tonic()
        .with_endpoint(&endpoint)
        .build_span_exporter() {
        Ok(exporter) => {
            println!("Successfully created OTLP span exporter");
            SdkTracerProvider::builder()
                .with_batch_exporter(exporter, opentelemetry_sdk::runtime::Tokio)
                .build()
        },
        Err(e) => {
            eprintln!("Failed to create OTLP span exporter: {:?}, using no-op provider", e);
            SdkTracerProvider::builder()
                .build()
        }
    };

    global::set_tracer_provider(tracer_provider);
    
    global::set_text_map_propagator(TraceContextPropagator::new());
    
    println!("TracerProvider initialized successfully");

    let meter_provider = SdkMeterProvider::builder()
        .with_resource(resource)
        .build();

    global::set_meter_provider(meter_provider);

    Ok(())
}
