import http from 'http';
import { diag, DiagConsoleLogger, DiagLogLevel, context } from '@opentelemetry/api';
import { NodeTracerProvider } from '@opentelemetry/sdk-trace-node';
import { SimpleSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc';
import { Resource } from '@opentelemetry/resources';
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions';

diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.INFO);

// Configuración del proveedor de trazas
const provider = new NodeTracerProvider({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: 'api-gateway',
  }),
});

// Configuración del exportador para Jaeger
const exporter = new OTLPTraceExporter({
  url: 'http://localhost:4317', // URL de tu colector de Jaeger en Kubernetes
});
provider.addSpanProcessor(new SimpleSpanProcessor(exporter));

// Registra el proveedor de trazas
provider.register();

const tracer = provider.getTracer('api-gateway');

const server = http.createServer((req, res) => {
  const span = tracer.startSpan(`Handling ${req.method} ${req.url}`);
  context.with(context.active(), () => {
    if (req.url === '/ping') {
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end('pong');
    } else {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not Found');
    }
    span.end();
  });
});

server.listen(3000, () => {
  console.log('API Gateway running on http://localhost:3000');
});
