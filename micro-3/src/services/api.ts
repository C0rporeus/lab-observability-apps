import { context, trace, SpanStatusCode } from '@opentelemetry/api';
import { logs, SeverityNumber } from '@opentelemetry/api-logs';
import { MetricsHandler } from '../observability/metrics';
import { MicroserviceClient } from '../clients/microservices';

// Helper function to log using OpenTelemetry
function logToOTel(level: 'info' | 'warn' | 'error', message: string, metadata?: any) {
  // Get logger each time to ensure LoggerProvider is configured
  const loggerProvider = logs.getLoggerProvider();
  if (!loggerProvider) {
    console.error('LoggerProvider not configured yet');
    return;
  }
  const otelLogger = loggerProvider.getLogger('api-gateway', '1.0.0');
  
  // Debug: verificar si el logger está funcionando
  console.log(`[DEBUG] logToOTel called: ${level} - ${message}`);
  
  const activeSpan = trace.getActiveSpan();
  
  let severityNumber = SeverityNumber.INFO;
  let severityText = 'INFO';
  
  if (level === 'warn') {
    severityNumber = SeverityNumber.WARN;
    severityText = 'WARN';
  } else if (level === 'error') {
    severityNumber = SeverityNumber.ERROR;
    severityText = 'ERROR';
  }
  
  const attributes: any = {};
  
  if (activeSpan) {
    const spanContext = activeSpan.spanContext();
    if (spanContext.traceId && spanContext.spanId) {
      attributes['trace.id'] = spanContext.traceId;
      attributes['span.id'] = spanContext.spanId;
      attributes['trace.flags'] = spanContext.traceFlags?.toString(16).padStart(2, '0') || '00';
    }
  }
  
  if (metadata) {
    Object.assign(attributes, metadata);
  }
  
  try {
    otelLogger.emit({
      severityNumber,
      severityText,
      body: message,
      attributes,
    });
    console.log(`[DEBUG] Log emitted successfully: ${message}`);
  } catch (error) {
    console.error(`[ERROR] Failed to emit log:`, error);
  }
}

export class ApiService {
  private metricsHandler: MetricsHandler;
  private microserviceClient: MicroserviceClient;
  private requestCounter: number = 0;
  private errorCounter: number = 0;

  constructor(metricsHandler: MetricsHandler) {
    this.metricsHandler = metricsHandler;
    this.microserviceClient = new MicroserviceClient();
  }

  private async safeExecute<T>(
    operation: () => Promise<T>,
    operationName: string,
    fallbackValue: T
  ): Promise<T> {
    try {
      return await operation();
    } catch (error) {
      this.errorCounter++;
      logToOTel('error', `Error in ${operationName}:`, { 
        error: error instanceof Error ? error.message : String(error),
        errorCounter: this.errorCounter 
      });
      return fallbackValue;
    }
  }

  private recordMetricsSafely(endpoint: string, method: string): void {
    try {
      this.metricsHandler.recordRequest(endpoint, method);
    } catch (error) {
      logToOTel('warn', 'Failed to record metrics:', error);
    }
  }

  async handleMicro1(): Promise<{ statusCode: number; body: string }> {
    this.requestCounter++;
    
    return await this.safeExecute(async () => {
      logToOTel('info', `Calling micro-1 #${this.requestCounter}`);
      this.recordMetricsSafely('/micro1', 'GET');
      
      const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(() => reject(new Error('Request timeout')), 5000);
      });
      
      const responsePromise = this.microserviceClient.pingMicro1();
      const response = await Promise.race([responsePromise, timeoutPromise]);
      
      return {
        statusCode: 200,
        body: JSON.stringify({
          ...response,
          requestNumber: this.requestCounter,
          timestamp: new Date().toISOString()
        })
      };
    }, 'handleMicro1', {
      statusCode: 503,
      body: JSON.stringify({ 
        error: 'Micro-1 service unavailable',
        requestNumber: this.requestCounter,
        timestamp: new Date().toISOString()
      })
    });
  }

  async handleMicro2(): Promise<{ statusCode: number; body: string }> {
    this.requestCounter++;
    
    return await this.safeExecute(async () => {
      logToOTel('info', `Calling micro-2 #${this.requestCounter}`);
      this.recordMetricsSafely('/micro2', 'GET');
      
      const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(() => reject(new Error('Request timeout')), 5000);
      });
      
      const responsePromise = this.microserviceClient.pingMicro2();
      const response = await Promise.race([responsePromise, timeoutPromise]);
      
      return {
        statusCode: 200,
        body: JSON.stringify({
          ...response,
          requestNumber: this.requestCounter,
          timestamp: new Date().toISOString()
        })
      };
    }, 'handleMicro2', {
      statusCode: 503,
      body: JSON.stringify({ 
        error: 'Micro-2 service unavailable',
        requestNumber: this.requestCounter,
        timestamp: new Date().toISOString()
      })
    });
  }

  handleNotFound(): { statusCode: number; body: string } {
    this.requestCounter++;
    logToOTel('warn', `Route not found #${this.requestCounter}`);
    
    this.recordMetricsSafely('unknown', 'GET');
    
    return {
      statusCode: 404,
      body: JSON.stringify({ 
        error: 'Not Found',
        requestNumber: this.requestCounter,
        timestamp: new Date().toISOString()
      })
    };
  }

  getHealthStatus(): { statusCode: number; body: string } {
    return {
      statusCode: 200,
      body: JSON.stringify({
        status: 'healthy',
        totalRequests: this.requestCounter,
        totalErrors: this.errorCounter,
        uptime: process.uptime(),
        timestamp: new Date().toISOString()
      })
    };
  }

  async handleGetWeatherMicro1(city: string): Promise<{ statusCode: number; body: string }> {
    this.requestCounter++;
    
    return await this.safeExecute(async () => {
      logToOTel('info', `Calling micro-1 GetWeather for ${city}`);
      this.recordMetricsSafely('/weather/micro1', 'GET');
      
      const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(() => reject(new Error('Request timeout')), 30000);
      });
      
      const responsePromise = this.microserviceClient.getWeatherMicro1(city);
      const response = await Promise.race([responsePromise, timeoutPromise]);
      
      return {
        statusCode: 200,
        body: JSON.stringify({
          ...response,
          requestNumber: this.requestCounter,
          timestamp: new Date().toISOString()
        })
      };
    }, 'handleGetWeatherMicro1', {
      statusCode: 503,
      body: JSON.stringify({ 
        error: 'Weather service unavailable',
        requestNumber: this.requestCounter,
        timestamp: new Date().toISOString()
      })
    });
  }

  async handleSaveWeatherDataMicro1(city: string, temperature: number, condition: string, humidity: number, windSpeed: number): Promise<{ statusCode: number; body: string }> {
    this.requestCounter++;
    
    return await this.safeExecute(async () => {
      logToOTel('info', `Calling micro-1 SaveWeatherData for ${city}`);
      this.recordMetricsSafely('/weather/micro1/save', 'POST');
      
      const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(() => reject(new Error('Request timeout')), 30000);
      });
      
      const responsePromise = this.microserviceClient.saveWeatherDataMicro1(city, temperature, condition, humidity, windSpeed);
      const response = await Promise.race([responsePromise, timeoutPromise]);
      
      return {
        statusCode: 200,
        body: JSON.stringify({
          ...response,
          requestNumber: this.requestCounter,
          timestamp: new Date().toISOString()
        })
      };
    }, 'handleSaveWeatherDataMicro1', {
      statusCode: 503,
      body: JSON.stringify({ 
        error: 'Weather service unavailable',
        requestNumber: this.requestCounter,
        timestamp: new Date().toISOString()
      })
    });
  }

  async handleGetWeatherHistoryMicro1(city: string, limit: number): Promise<{ statusCode: number; body: string }> {
    this.requestCounter++;
    
    return await this.safeExecute(async () => {
      logToOTel('info', `Calling micro-1 GetWeatherHistory: city="${city}", limit=${limit}`);
      this.recordMetricsSafely('/weather/micro1/history', 'GET');
      
      const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(() => reject(new Error('Request timeout')), 30000);
      });
      
      const responsePromise = this.microserviceClient.getWeatherHistoryMicro1(city, limit);
      const response = await Promise.race([responsePromise, timeoutPromise]);
      
      return {
        statusCode: 200,
        body: JSON.stringify({
          ...response,
          requestNumber: this.requestCounter,
          timestamp: new Date().toISOString()
        })
      };
    }, 'handleGetWeatherHistoryMicro1', {
      statusCode: 503,
      body: JSON.stringify({ 
        error: 'Weather history service unavailable',
        requestNumber: this.requestCounter,
        timestamp: new Date().toISOString()
      })
    });
  }

  async handleGetWeatherMicro2(city: string): Promise<{ statusCode: number; body: string }> {
    this.requestCounter++;
    
    return await this.safeExecute(async () => {
      logToOTel('info', `Calling micro-2 GetWeather for ${city}`);
      this.recordMetricsSafely('/weather/micro2', 'GET');
      
      const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(() => reject(new Error('Request timeout')), 30000);
      });
      
      const responsePromise = this.microserviceClient.getWeatherMicro2(city);
      const response = await Promise.race([responsePromise, timeoutPromise]);
      
      return {
        statusCode: 200,
        body: JSON.stringify({
          ...response,
          requestNumber: this.requestCounter,
          timestamp: new Date().toISOString()
        })
      };
    }, 'handleGetWeatherMicro2', {
      statusCode: 503,
      body: JSON.stringify({ 
        error: 'Weather service unavailable',
        requestNumber: this.requestCounter,
        timestamp: new Date().toISOString()
      })
    });
  }

  async handleSaveWeatherDataMicro2(city: string, temperature: number, condition: string, humidity: number, windSpeed: number): Promise<{ statusCode: number; body: string }> {
    this.requestCounter++;
    
    return await this.safeExecute(async () => {
      logToOTel('info', `Calling micro-2 SaveWeatherData for ${city}`);
      this.recordMetricsSafely('/weather/micro2/save', 'POST');
      
      const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(() => reject(new Error('Request timeout')), 30000);
      });
      
      const responsePromise = this.microserviceClient.saveWeatherDataMicro2(city, temperature, condition, humidity, windSpeed);
      const response = await Promise.race([responsePromise, timeoutPromise]);
      
      return {
        statusCode: 200,
        body: JSON.stringify({
          ...response,
          requestNumber: this.requestCounter,
          timestamp: new Date().toISOString()
        })
      };
    }, 'handleSaveWeatherDataMicro2', {
      statusCode: 503,
      body: JSON.stringify({ 
        error: 'Weather service unavailable',
        requestNumber: this.requestCounter,
        timestamp: new Date().toISOString()
      })
    });
  }

  async handleGetWeatherHistoryMicro2(city: string, limit: number): Promise<{ statusCode: number; body: string }> {
    this.requestCounter++;
    
    return await this.safeExecute(async () => {
      logToOTel('info', `Calling micro-2 GetWeatherHistory: city="${city}", limit=${limit}`);
      this.recordMetricsSafely('/weather/micro2/history', 'GET');
      
      const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(() => reject(new Error('Request timeout')), 30000);
      });
      
      const responsePromise = this.microserviceClient.getWeatherHistoryMicro2(city, limit);
      const response = await Promise.race([responsePromise, timeoutPromise]);
      
      return {
        statusCode: 200,
        body: JSON.stringify({
          ...response,
          requestNumber: this.requestCounter,
          timestamp: new Date().toISOString()
        })
      };
    }, 'handleGetWeatherHistoryMicro2', {
      statusCode: 503,
      body: JSON.stringify({ 
        error: 'Weather history service unavailable',
        requestNumber: this.requestCounter,
        timestamp: new Date().toISOString()
      })
    });
  }
}
