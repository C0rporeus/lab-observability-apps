import { diag, DiagConsoleLogger, DiagLogLevel, metrics } from '@opentelemetry/api';
import { logs, SeverityNumber } from '@opentelemetry/api-logs';
import { NodeTracerProvider } from '@opentelemetry/sdk-trace-node';
import { MeterProvider } from '@opentelemetry/sdk-metrics';
import { LoggerProvider, BatchLogRecordProcessor } from '@opentelemetry/sdk-logs';
import { Resource } from '@opentelemetry/resources';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-http';
import { OTLPLogExporter } from '@opentelemetry/exporter-logs-otlp-http';
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions';
import { PeriodicExportingMetricReader } from '@opentelemetry/sdk-metrics';

export function initObservability(): LoggerProvider {
  diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.INFO);

  const resource = new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: 'api-gateway',
    'application': 'lab-observability',
  });

  const provider = new NodeTracerProvider({
    resource: resource,
  });

  provider.addSpanProcessor(
    new BatchSpanProcessor(
      new OTLPTraceExporter({
        url: 'http://otel-collector:4318/v1/traces',
      })
    )
  );

  provider.register();

  const meterProvider = new MeterProvider({
    resource: resource,
    readers: [
      new PeriodicExportingMetricReader({
        exporter: new OTLPMetricExporter({
          url: 'http://otel-collector:4318/v1/metrics',
        }),
      }),
    ],
  });

  metrics.setGlobalMeterProvider(meterProvider);

  // Initialize LoggerProvider for logs
  const loggerProvider = new LoggerProvider({
    resource: resource,
  });

  loggerProvider.addLogRecordProcessor(
    new BatchLogRecordProcessor(
      new OTLPLogExporter({
        url: 'http://otel-collector:4318/v1/logs',
      }),
      {
        maxExportBatchSize: 10,  // Reducir batch size para envío más rápido
        scheduledDelayMillis: 1000,  // Reducir delay a 1 segundo
        exportTimeoutMillis: 10000,
      }
    )
  );

  logs.setGlobalLoggerProvider(loggerProvider);

  return loggerProvider;
}
