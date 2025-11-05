use crate::observability::MetricsHandler;
use crate::helloworld::{HelloWorldResponse, MessageRequest, MessageResponse};
use tracing::info;

#[derive(Debug)]
pub struct GreeterService {
    pub metrics: MetricsHandler,
}

impl GreeterService {
    pub fn new() -> Self {
        Self {
            metrics: MetricsHandler::new(),
        }
    }

    pub fn send_message(&self, request: &MessageRequest) -> MessageResponse {
        let message = &request.message;
        info!("Processing message: {}", message);
        
        let reply = format!("Reply to: {}", message);
        
        self.metrics.record_message_processed("send_message");
        
        MessageResponse { reply }
    }

    pub fn get_hello_world(&self) -> HelloWorldResponse {
        info!("Processing hello world request");
        
        self.metrics.record_hello_world_request("get_hello_world");
        
        HelloWorldResponse {
            greeting: "Hello World!".to_string(),
        }
    }
}
