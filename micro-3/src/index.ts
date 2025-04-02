import http from 'http';
import * as protoLoader from '@grpc/proto-loader';
import * as grpc from '@grpc/grpc-js';
import { diag, DiagConsoleLogger, DiagLogLevel, context } from '@opentelemetry/api';
import { NodeTracerProvider } from '@opentelemetry/sdk-trace-node';
import { Resource } from '@opentelemetry/resources';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions';
import winston from 'winston';


const PROTO_PATH = __dirname + '/micro.proto';
const packageDefinition = protoLoader.loadSync(PROTO_PATH, {
  keepCase: true,
  longs: String,
  enums: String,
  defaults: true,
  oneofs: true,
});
const microProto = grpc.loadPackageDefinition(packageDefinition).micro as any;

const micro1Client = new microProto.MicroService('micro-1:50051', grpc.credentials.createInsecure());
const micro2Client = new microProto.MicroService('micro-2:50051', grpc.credentials.createInsecure());

diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.INFO);

const provider = new NodeTracerProvider({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: 'api-gateway',
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
    } else if (req.url === '/micro1') {
      micro1Client.Ping({}, (err: any, response: any) => {
        if (err) {
          console.error('Error calling micro-1:', err);
          res.writeHead(500);
          res.end('Error calling micro-1');
          return;
        }
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(response));
      });
    } else if (req.url === '/micro2') {
      micro2Client.Ping({}, (err: any, response: any) => {
        if (err) {
          console.error('Error calling micro-2:', err);
          res.writeHead(500);
          res.end('Error calling micro-2');
          return;
        }
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(response));
      });
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