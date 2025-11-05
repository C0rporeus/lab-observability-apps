import http from 'http';
import { context, trace, SpanStatusCode } from '@opentelemetry/api';
import { logs, SeverityNumber } from '@opentelemetry/api-logs';
import { initObservability } from './config/observability';
import { MetricsHandler } from './observability/metrics';
import { ApiService } from './services/api';

let loggerProvider: any = null;
try {
  loggerProvider = initObservability();
  console.log('Observability initialized successfully');
} catch (error) {
  console.error('Failed to initialize observability:', error);
}

// Get the logger from OpenTelemetry
const logger = logs.getLoggerProvider().getLogger('api-gateway', '1.0.0');

process.on('SIGTERM', () => {
  logger.emit({
    severityNumber: SeverityNumber.INFO,
    severityText: 'INFO',
    body: 'SIGTERM received, shutting down gracefully...',
    attributes: {
      'event.name': 'shutdown',
    },
  });
  if (loggerProvider) {
    loggerProvider.shutdown();
  }
  process.exit(0);
});

const metricsHandler = new MetricsHandler();
const apiService = new ApiService(metricsHandler);

const tracer = trace.getTracer('api-gateway');

let totalRequests = 0;
let errorCount = 0;

const parseRequestBody = (req: http.IncomingMessage): Promise<any> => {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => {
      body += chunk.toString();
    });
    req.on('end', () => {
      try {
        resolve(JSON.parse(body));
      } catch (error) {
        reject(new Error('Invalid JSON'));
      }
    });
    req.on('error', reject);
  });
};

const server = http.createServer(async (req, res) => {
  totalRequests++;
  const startTime = Date.now();
  const requestId = totalRequests;
  
  const span = tracer.startSpan(`Handling ${req.method} ${req.url}`, {
    attributes: {
      'http.method': req.method || 'UNKNOWN',
      'http.url': req.url || '/unknown',
      'request.id': requestId,
    }
  });
  
  const timeout = setTimeout(() => {
    if (!res.headersSent) {
      console.error(`Request ${requestId} timed out`);
      res.writeHead(504, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ 
        error: 'Gateway timeout',
        requestId,
        timestamp: new Date().toISOString()
      }));
      span.setStatus({ code: SpanStatusCode.ERROR, message: 'Gateway timeout' });
      span.end();
    }
  }, 30000);
  
  context.with(trace.setSpan(context.active(), span), async () => {
    let response;
    
    try {
      const activeSpan = trace.getActiveSpan();
      if (activeSpan) {
        const spanContext = activeSpan.spanContext();
        logger.emit({
          severityNumber: SeverityNumber.INFO,
          severityText: 'INFO',
          body: `Processing request #${requestId}: ${req.method} ${req.url}`,
          attributes: {
            'request.id': requestId,
            'trace.id': spanContext.traceId,
            'span.id': spanContext.spanId,
          },
        });
      } else {
        logger.emit({
          severityNumber: SeverityNumber.INFO,
          severityText: 'INFO',
          body: `Processing request #${requestId}: ${req.method} ${req.url}`,
          attributes: {
            'request.id': requestId,
          },
        });
      }
      
      if (req.url === '/micro1') {
        response = await apiService.handleMicro1();
      } else if (req.url === '/micro2') {
        response = await apiService.handleMicro2();
      } else if (req.url?.startsWith('/weather/micro1/history/')) {
        const urlParts = req.url.split('/').filter(p => p !== '');
        let city = '';
        let limit = 10;
        if (urlParts.length >= 4 && urlParts[3] === 'history') {
          if (urlParts.length >= 5) {
            const potentialLimit = parseInt(urlParts[4]);
            if (!isNaN(potentialLimit)) {
              limit = potentialLimit;
            } else {
              city = urlParts[4];
              if (urlParts.length >= 6) {
                limit = parseInt(urlParts[5]) || 10;
              }
            }
          }
        }
        response = await apiService.handleGetWeatherHistoryMicro1(city, limit);
      } else if (req.url?.startsWith('/weather/micro1?')) {
        const urlParams = new URLSearchParams(req.url.split('?')[1]);
        const city = urlParams.get('city') || '';
        response = await apiService.handleGetWeatherMicro1(city);
      } else if (req.url === '/weather/micro1') {
        response = apiService.handleNotFound();
      } else if (req.url?.startsWith('/weather/micro2/history/')) {
        const urlParts = req.url.split('/').filter(p => p !== '');
        let city = '';
        let limit = 10;
        if (urlParts.length >= 4 && urlParts[3] === 'history') {
          if (urlParts.length >= 5) {
            const potentialLimit = parseInt(urlParts[4]);
            if (!isNaN(potentialLimit)) {
              limit = potentialLimit;
            } else {
              city = urlParts[4];
              if (urlParts.length >= 6) {
                limit = parseInt(urlParts[5]) || 10;
              }
            }
          }
        }
        response = await apiService.handleGetWeatherHistoryMicro2(city, limit);
      } else if (req.url?.startsWith('/weather/micro2?')) {
        const urlParams = new URLSearchParams(req.url.split('?')[1]);
        const city = urlParams.get('city') || '';
        response = await apiService.handleGetWeatherMicro2(city);
      } else if (req.url === '/weather/micro2') {
        response = apiService.handleNotFound();
      } else if (req.method === 'POST' && req.url === '/weather/micro2/save') {
        const body = await parseRequestBody(req);
        response = await apiService.handleSaveWeatherDataMicro2(
          body.city || '',
          body.temperature || 0,
          body.condition || '',
          body.humidity || 0,
          body.windSpeed || 0
        );
      } else if (req.url === '/health') {
        response = apiService.getHealthStatus();
      } else if (req.url === '/metrics') {
        response = {
          statusCode: 200,
          body: `# HELP api_gateway_requests_total Total number of requests
# TYPE api_gateway_requests_total counter
api_gateway_requests_total ${totalRequests}
# HELP api_gateway_errors_total Total number of errors
# TYPE api_gateway_errors_total counter
api_gateway_errors_total ${errorCount}
`
        };
      } else {
        response = apiService.handleNotFound();
      }
      
      if (!res.headersSent) {
        const contentType = req.url === '/metrics' ? 'text/plain' : 'application/json';
        res.writeHead(response.statusCode, { 
          'Content-Type': contentType,
          'X-Request-ID': requestId.toString()
        });
        res.end(response.body);
      }
      
      if (response.statusCode < 400) {
        span.setStatus({ code: SpanStatusCode.OK });
      } else {
        span.setStatus({ code: SpanStatusCode.ERROR });
      }
      
    } catch (error) {
      errorCount++;
      const activeSpan = trace.getActiveSpan();
      if (activeSpan) {
        const spanContext = activeSpan.spanContext();
        logger.emit({
          severityNumber: SeverityNumber.ERROR,
          severityText: 'ERROR',
          body: `Error handling request #${requestId}`,
          attributes: {
            'request.id': requestId,
            'error': error instanceof Error ? error.message : String(error),
            'trace.id': spanContext.traceId,
            'span.id': spanContext.spanId,
          },
        });
      } else {
        logger.emit({
          severityNumber: SeverityNumber.ERROR,
          severityText: 'ERROR',
          body: `Error handling request #${requestId}:`,
          attributes: {
            'request.id': requestId,
            'error': error instanceof Error ? error.message : String(error),
          },
        });
      }
      
      if (!res.headersSent) {
        res.writeHead(500, { 
          'Content-Type': 'application/json',
          'X-Request-ID': requestId.toString()
        });
        res.end(JSON.stringify({ 
          error: 'Internal server error',
          requestId,
          timestamp: new Date().toISOString()
        }));
      }
      
      span.setStatus({ 
        code: SpanStatusCode.ERROR, 
        message: error instanceof Error ? error.message : String(error)
      });
    } finally {
      clearTimeout(timeout);
      
      try {
        const duration = (Date.now() - startTime) / 1000;
        const endpoint = req.url || 'unknown';
        metricsHandler.recordRequestDuration(duration, endpoint, req.method || 'GET');
        
        span.setAttributes({
          'http.status_code': res.statusCode || 500,
          'http.response.duration_ms': (Date.now() - startTime),
        });
      } catch (metricsError) {
      const activeSpan = trace.getActiveSpan();
      if (activeSpan) {
        const spanContext = activeSpan.spanContext();
        logger.emit({
          severityNumber: SeverityNumber.ERROR,
          severityText: 'ERROR',
          body: 'Failed to record metrics',
          attributes: {
            'error': metricsError instanceof Error ? metricsError.message : String(metricsError),
            'trace.id': spanContext.traceId,
            'span.id': spanContext.spanId,
          },
        });
      } else {
        logger.emit({
          severityNumber: SeverityNumber.ERROR,
          severityText: 'ERROR',
          body: 'Failed to record metrics:',
          attributes: {
            'error': metricsError instanceof Error ? metricsError.message : String(metricsError),
          },
        });
      }
      }
      
      span.end();
    }
  });
});

server.on('error', (error) => {
  console.error('Server error:', error);
});

process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully...');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('SIGINT received, shutting down gracefully...');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});

server.listen(3000, () => {
  console.log(`API Gateway server listening on port 3000`);
  console.log(`Process ID: ${process.pid}`);
  console.log(`Uptime: ${process.uptime()}s`);
});

process.on('uncaughtException', (error) => {
  console.error('Uncaught Exception:', error);
});

process.on('unhandledRejection', (reason) => {
  console.error('Unhandled Rejection:', reason);
});