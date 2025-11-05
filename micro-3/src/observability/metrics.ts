import { metrics } from '@opentelemetry/api';

export class MetricsHandler {
  private requestCounter;
  private requestDuration;

  constructor() {
    const meter = metrics.getMeter('api-gateway');
    
    this.requestCounter = meter.createCounter('http_requests_total', {
      description: 'Total number of HTTP requests',
    });
    
    this.requestDuration = meter.createHistogram('http_request_duration_seconds', {
      description: 'HTTP request duration in seconds',
    });
  }

  recordRequest(endpoint: string, method: string): void {
    this.requestCounter.add(1, { endpoint, method });
  }

  recordRequestDuration(duration: number, endpoint: string, method: string): void {
    this.requestDuration.record(duration, { endpoint, method });
  }
}
