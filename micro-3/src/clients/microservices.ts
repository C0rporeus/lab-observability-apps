import * as protoLoader from '@grpc/proto-loader';
import * as grpc from '@grpc/grpc-js';
import path from 'path';
import { context, trace, propagation } from '@opentelemetry/api';

// Load micro-1 (Greeter service) proto definition
const MICRO1_PROTO_PATHS = [
  path.join(process.cwd(), 'micro1.proto'),
  path.join(__dirname, '..', 'micro1.proto'),
  path.join(__dirname, '..', '..', 'micro1.proto'),
  '/app/micro1.proto'
];

let micro1PackageDefinition: any = null;
let micro1Proto: any = null;

for (const protoPath of MICRO1_PROTO_PATHS) {
  try {
    console.log(`Trying to load micro1.proto from: ${protoPath}`);
    micro1PackageDefinition = protoLoader.loadSync(protoPath, {
      keepCase: true,
      longs: String,
      enums: String,
      defaults: true,
      oneofs: true,
    });
    micro1Proto = grpc.loadPackageDefinition(micro1PackageDefinition).helloworld as any;
    console.log(`Successfully loaded micro1.proto from: ${protoPath}`);
    break;
  } catch (error) {
    console.log(`Failed to load micro1.proto from ${protoPath}:`, error instanceof Error ? error.message : String(error));
    continue;
  }
}

if (!micro1Proto) {
  console.error('Failed to load micro1.proto from any path');
  throw new Error('Could not load micro1.proto definition');
}

// Load micro-2 (MicroService) proto definition
const MICRO2_PROTO_PATH = path.join(process.cwd(), 'micro.proto');
const micro2PackageDefinition = protoLoader.loadSync(MICRO2_PROTO_PATH, {
  keepCase: true,
  longs: String,
  enums: String,
  defaults: true,
  oneofs: true,
});
const micro2Proto = grpc.loadPackageDefinition(micro2PackageDefinition).micro as any;

export class MicroserviceClient {
  private micro1Client: any;
  private micro2Client: any;

  constructor() {
    // micro-1 uses Greeter service
    this.micro1Client = new micro1Proto.Greeter('micro-1:50051', grpc.credentials.createInsecure());
    
    // micro-2 uses MicroService (for now we'll try to connect, but it may not be implemented yet)
    try {
      this.micro2Client = new micro2Proto.MicroService('micro-2:50051', grpc.credentials.createInsecure());
    } catch (err) {
      console.warn('Warning: Could not create micro-2 client:', err);
      this.micro2Client = null;
    }
  }

  // Use the correct method for micro-1: GetHelloWorld instead of Ping
  async pingMicro1(): Promise<any> {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Request timeout'));
      }, 5000);

      // Create metadata with tracing context
      const metadata = new grpc.Metadata();
      
      // Inject tracing context into metadata
      propagation.inject(context.active(), metadata, {
        set: (metadata, key, value) => {
          metadata.set(key, value);
        }
      });

      this.micro1Client.GetHelloWorld({}, metadata, (err: any, response: any) => {
        clearTimeout(timeout);
        if (err) {
          reject(err);
        } else {
          resolve(response);
        }
      });
    });
  }

  // Try to ping micro-2, but handle gracefully if not implemented
  async pingMicro2(): Promise<any> {
    if (!this.micro2Client) {
      throw new Error('Micro-2 client not available');
    }

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Request timeout'));
      }, 5000);

      // Create metadata with tracing context
      const metadata = new grpc.Metadata();
      
      // Inject tracing context into metadata
      propagation.inject(context.active(), metadata, {
        set: (metadata, key, value) => {
          metadata.set(key, value);
        }
      });

      this.micro2Client.Ping({}, metadata, (err: any, response: any) => {
        clearTimeout(timeout);
        if (err) {
          reject(err);
        } else {
          resolve(response);
        }
      });
    });
  }

  // Additional method for testing micro-1 SendMessage functionality
  async sendMessageMicro1(message: string): Promise<any> {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Request timeout'));
      }, 5000);

      // Create metadata with tracing context
      const metadata = new grpc.Metadata();
      
      // Inject tracing context into metadata
      propagation.inject(context.active(), metadata, {
        set: (metadata, key, value) => {
          metadata.set(key, value);
        }
      });

      this.micro1Client.SendMessage({ message }, metadata, (err: any, response: any) => {
        clearTimeout(timeout);
        if (err) {
          reject(err);
        } else {
          resolve(response);
        }
      });
    });
  }

  // Weather methods for micro-1
  async getWeatherMicro1(city: string): Promise<any> {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Request timeout'));
      }, 5000);

      const metadata = new grpc.Metadata();
      propagation.inject(context.active(), metadata, {
        set: (metadata, key, value) => {
          metadata.set(key, value);
        }
      });

      this.micro1Client.GetWeather({ city }, metadata, (err: any, response: any) => {
        clearTimeout(timeout);
        if (err) {
          reject(err);
        } else {
          resolve(response);
        }
      });
    });
  }

  async saveWeatherDataMicro1(city: string, temperature: number, condition: string, humidity: number, windSpeed: number): Promise<any> {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Request timeout'));
      }, 5000);

      const metadata = new grpc.Metadata();
      propagation.inject(context.active(), metadata, {
        set: (metadata, key, value) => {
          metadata.set(key, value);
        }
      });

      this.micro1Client.SaveWeatherData({ city, temperature, condition, humidity, wind_speed: windSpeed }, metadata, (err: any, response: any) => {
        clearTimeout(timeout);
        if (err) {
          reject(err);
        } else {
          resolve(response);
        }
      });
    });
  }

  async getWeatherHistoryMicro1(city: string, limit: number): Promise<any> {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Request timeout'));
      }, 5000);

      const metadata = new grpc.Metadata();
      propagation.inject(context.active(), metadata, {
        set: (metadata, key, value) => {
          metadata.set(key, value);
        }
      });

      this.micro1Client.GetWeatherHistory({ city, limit }, metadata, (err: any, response: any) => {
        clearTimeout(timeout);
        if (err) {
          reject(err);
        } else {
          resolve(response);
        }
      });
    });
  }

  // Weather methods for micro-2
  async getWeatherMicro2(city: string): Promise<any> {
    if (!this.micro2Client) {
      throw new Error('Micro-2 client not available');
    }

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Request timeout'));
      }, 5000);

      const metadata = new grpc.Metadata();
      propagation.inject(context.active(), metadata, {
        set: (metadata, key, value) => {
          metadata.set(key, value);
        }
      });

      this.micro2Client.GetWeather({ city }, metadata, (err: any, response: any) => {
        clearTimeout(timeout);
        if (err) {
          reject(err);
        } else {
          resolve(response);
        }
      });
    });
  }

  async saveWeatherDataMicro2(city: string, temperature: number, condition: string, humidity: number, windSpeed: number): Promise<any> {
    if (!this.micro2Client) {
      throw new Error('Micro-2 client not available');
    }

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Request timeout'));
      }, 5000);

      const metadata = new grpc.Metadata();
      propagation.inject(context.active(), metadata, {
        set: (metadata, key, value) => {
          metadata.set(key, value);
        }
      });

      this.micro2Client.SaveWeatherData({ city, temperature, condition, humidity, wind_speed: windSpeed }, metadata, (err: any, response: any) => {
        clearTimeout(timeout);
        if (err) {
          reject(err);
        } else {
          resolve(response);
        }
      });
    });
  }

  async getWeatherHistoryMicro2(city: string, limit: number): Promise<any> {
    if (!this.micro2Client) {
      throw new Error('Micro-2 client not available');
    }

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Request timeout'));
      }, 5000);

      const metadata = new grpc.Metadata();
      propagation.inject(context.active(), metadata, {
        set: (metadata, key, value) => {
          metadata.set(key, value);
        }
      });

      this.micro2Client.GetWeatherHistory({ city, limit }, metadata, (err: any, response: any) => {
        clearTimeout(timeout);
        if (err) {
          reject(err);
        } else {
          resolve(response);
        }
      });
    });
  }
}
