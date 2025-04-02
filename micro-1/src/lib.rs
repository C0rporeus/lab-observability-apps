use opentelemetry::trace::TraceContextExt;
use tracing::{info, info_span, Instrument};

pub mod helloworld {
    tonic::include_proto!("helloworld");
}

use helloworld::greeter_server::Greeter;
use helloworld::{HelloWorldRequest, HelloWorldResponse, MessageRequest, MessageResponse};

#[derive(Debug, Default)]
pub struct GreeterService {}

#[tonic::async_trait]
impl Greeter for GreeterService {
    async fn send_message(
        &self,
        request: tonic::Request<MessageRequest>,
    ) -> Result<tonic::Response<MessageResponse>, tonic::Status> {
        let span = info_span!("send_message", request.message = ?request.get_ref().message);
        async {
            info!("Received message request");
            let reply = format!("Reply to: {}", request.get_ref().message);
            Ok(tonic::Response::new(MessageResponse { reply }))
        }
        .instrument(span)
        .await
    }

    async fn get_hello_world(
        &self,
        request: tonic::Request<HelloWorldRequest>,
    ) -> Result<tonic::Response<HelloWorldResponse>, tonic::Status> {
        let span = info_span!("get_hello_world");
        async {
            info!("Received hello world request");
            Ok(tonic::Response::new(HelloWorldResponse {
                greeting: "Hello World!".to_string(),
            }))
        }
        .instrument(span)
        .await
    }
}

