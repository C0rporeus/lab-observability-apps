import http from 'http';
import { diag, DiagConsoleLogger, DiagLogLevel, context } from '@opentelemetry/api';
import { NodeTracerProvider } from '@opentelemetry/sdk-trace-node';
import { Resource } from '@opentelemetry/resources';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions';
import winston from 'winston';

diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.INFO);

const provider = new NodeTracerProvider({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: 'micro-3',
    'application': 'lab-observability',
  }),
});

// Usa solo un exportador - el colector OpenTelemetry
provider.addSpanProcessor(
  new BatchSpanProcessor(
    new OTLPTraceExporter({
      url: 'http://otel-collector:4318/v1/traces',
    })
  )
);

// Registra el proveedor de trazas
provider.register();

const api = require('@opentelemetry/api');

const logger = winston.createLogger({
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json(),
    winston.format((info) => {
      const span = api.trace.getActiveSpan();
      if (span) {
        const context = span.spanContext();
        info.traceID = context.traceId;
        info.spanID = context.spanId;
      }
      return info;
    })()
  ),
  transports: [new winston.transports.Console()]
});

const tracer = provider.getTracer('api-gateway');

const server = http.createServer((req, res) => {
  const span = tracer.startSpan(`Handling ${req.method} ${req.url}`);
  context.with(context.active(), () => {
    if (req.url === '/ping') {
      logger.info(`Received ping request`);
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end('pong');
    } else {
      logger.warn(`Route not found: ${req.url}`);
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not Found');
    }
    span.end();
  });
});

server.listen(3000, () => {
  logger.info('Server listening on port 3000');
});