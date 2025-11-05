use opentelemetry::{global, trace::{Tracer, Span}, KeyValue, Context};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;

#[derive(Debug, Serialize, Deserialize)]
pub struct WeatherApiResponse {
    pub main: MainWeather,
    pub weather: Vec<WeatherCondition>,
    pub wind: Option<WindData>,
    pub name: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct MainWeather {
    pub temp: f64,
    pub humidity: i32,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct WeatherCondition {
    pub main: String,
    pub description: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct WindData {
    pub speed: f64,
}

#[derive(Debug)]
pub struct WeatherService {
    client: Client,
    api_key: String,
    base_url: String,
}

impl WeatherService {
    pub fn new(api_key: String) -> Self {
        let client = Client::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .expect("Failed to create HTTP client");
        
        Self {
            client,
            api_key,
            base_url: "https://api.openweathermap.org/data/2.5".to_string(),
        }
    }

    pub async fn get_weather(&self, ctx: &Context, city: &str) -> Result<(f64, String, i32, f64), Box<dyn std::error::Error + Send + Sync + 'static>> {
        let tracer = global::tracer("micro-1-weather");
        let mut span = tracer.start_with_context("http.get.weather", ctx);
        span.set_attribute(KeyValue::new("http.method", "GET"));
        span.set_attribute(KeyValue::new("http.url", format!("{}/weather?q={}&appid={}", self.base_url, city, self.api_key)));
        span.set_attribute(KeyValue::new("http.route", "/weather"));
        span.set_attribute(KeyValue::new("service.name", "openweathermap-api"));
        span.set_attribute(KeyValue::new("service.version", "2.5"));
        span.set_attribute(KeyValue::new("weather.city", city.to_string()));

        let url = format!("{}/weather?q={}&appid={}&units=metric", self.base_url, city, self.api_key);
        
        match self.client.get(&url).send().await {
            Ok(response) => {
                let status = response.status();
                span.set_attribute(KeyValue::new("http.status_code", status.as_u16() as i64));
                span.set_attribute(KeyValue::new("http.flavor", "1.1"));

                if status.is_success() {
                    match response.json::<WeatherApiResponse>().await {
                        Ok(data) => {
                            let temp = data.main.temp;
                            let condition = data.weather.first()
                                .map(|w| w.description.clone())
                                .unwrap_or_else(|| "unknown".to_string());
                            let humidity = data.main.humidity;
                            let wind_speed = data.wind.map(|w| w.speed).unwrap_or(0.0);
                            
                            span.set_attribute(KeyValue::new("weather.temperature", temp));
                            span.set_attribute(KeyValue::new("weather.condition", condition.clone()));
                            span.set_attribute(KeyValue::new("weather.humidity", humidity as i64));
                            span.set_attribute(KeyValue::new("weather.wind_speed", wind_speed));
                            span.set_attribute(KeyValue::new("http.response.size", ">0"));
                            span.set_status(opentelemetry::trace::Status::Ok);
                            span.end();
                            Ok((temp, condition, humidity, wind_speed))
                        }
                        Err(e) => {
                            span.set_attribute(KeyValue::new("error", true));
                            span.set_attribute(KeyValue::new("error.message", e.to_string()));
                            span.set_status(opentelemetry::trace::Status::Error {
                                description: e.to_string().into(),
                            });
                            span.end();
                            Err(Box::new(e))
                        }
                    }
                } else {
                    span.set_attribute(KeyValue::new("error", true));
                    span.set_attribute(KeyValue::new("error.message", format!("HTTP error: {}", status)));
                    span.set_status(opentelemetry::trace::Status::Error {
                        description: format!("HTTP error: {}", status).into(),
                    });
                    span.end();
                    Err(format!("HTTP error: {}", status).into())
                }
            }
            Err(e) => {
                span.set_attribute(KeyValue::new("error", true));
                span.set_attribute(KeyValue::new("error.message", e.to_string()));
                span.set_attribute(KeyValue::new("http.status_code", 0));
                span.set_status(opentelemetry::trace::Status::Error {
                    description: e.to_string().into(),
                });
                span.end();
                Err(Box::new(e))
            }
        }
    }
}
