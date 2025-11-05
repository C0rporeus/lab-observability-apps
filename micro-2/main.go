package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	"micro-2/config"
	"micro-2/db"
	pb "micro-2/proto"
	"micro-2/weather"
	"runtime"

	"strings"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	otellog "go.opentelemetry.io/otel/log"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/reflection"
)

func main() {
	mp, err := config.InitMetrics()
	if err != nil {
		log.Fatalf("Error initializing metrics: %v", err)
	}
	defer func() {
		if err := mp.Shutdown(context.Background()); err != nil {
			log.Printf("Error shutting down metrics provider: %v", err)
		}
	}()

	_, err = config.InitTracer()
	if err != nil {
		log.Fatalf("Error initializing tracer: %v", err)
	}
	defer func() {
		if err := config.MainTracerProvider.Shutdown(context.Background()); err != nil {
			log.Printf("Error shutting down main tracer provider: %v", err)
		}
		if err := config.WeatherTracerProvider.Shutdown(context.Background()); err != nil {
			log.Printf("Error shutting down weather tracer provider: %v", err)
		}
		if err := config.DBTracerProvider.Shutdown(context.Background()); err != nil {
			log.Printf("Error shutting down DB tracer provider: %v", err)
		}
	}()

	_, err = config.InitLogger()
	if err != nil {
		log.Fatalf("Error initializing logger: %v", err)
	}
	defer func() {
		if err := config.MainLoggerProvider.Shutdown(context.Background()); err != nil {
			log.Printf("Error shutting down logger provider: %v", err)
		}
	}()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	logWithContext(context.Background(), "info", "Starting micro-2 service...", nil)
	logWithContext(context.Background(), "info", "Application running. Press Ctrl+C to stop.", nil)

	go func() {
		if err := startGRPCServer(); err != nil {
			logWithContext(context.Background(), "error", "Failed to start gRPC server", map[string]interface{}{
				"error": err.Error(),
			})
		}
	}()

	<-sigChan
	logWithContext(context.Background(), "info", "Shutdown signal received, shutting down gracefully...", nil)
	time.Sleep(2 * time.Second)
	logWithContext(context.Background(), "info", "Micro-2 service stopped", nil)
}

type microServiceImpl struct {
	pb.UnimplementedMicroServiceServer
	counter        int64
	weatherService *weather.WeatherService
	db             *db.Database
}

func (s *microServiceImpl) Ping(ctx context.Context, req *pb.PingRequest) (*pb.PingResponse, error) {
	startTime := time.Now()
	tracer := otel.Tracer("micro-2")
	ctx, span := tracer.Start(ctx, "micro-2: Ping",
		trace.WithAttributes(
			attribute.String("rpc.system", "grpc"),
			attribute.String("rpc.service", "micro.MicroService"),
			attribute.String("rpc.method", "Ping"),
			attribute.String("rpc.grpc.status_code", "0"),
			attribute.String("service.name", "micro-2"),
			attribute.String("service.version", "1.0.0"),
			attribute.String("service.language", "go"),
			attribute.String("service.framework", "grpc"),
			attribute.String("runtime.name", runtime.Compiler),
			attribute.String("runtime.version", runtime.Version()),
			attribute.String("runtime.os", runtime.GOOS),
			attribute.String("runtime.arch", runtime.GOARCH),
			attribute.Int("runtime.num_goroutines", runtime.NumGoroutine()),
		),
	)
	defer span.End()

	s.counter++

	span.SetAttributes(
		attribute.Int64("request.counter", s.counter),
		attribute.String("request.id", fmt.Sprintf("req-%d", s.counter)),
		attribute.String("request.timestamp", startTime.Format(time.RFC3339Nano)),
	)

	logWithContext(ctx, "info", "Processing Ping request in micro-2", map[string]interface{}{
		"counter": s.counter,
	})

	response := &pb.PingResponse{
		Message: fmt.Sprintf("Pong from micro-2! Counter: %d", s.counter),
	}

	duration := time.Since(startTime)
	span.SetAttributes(
		attribute.String("response.message", response.Message),
		attribute.Bool("response.success", true),
		attribute.Int64("response.duration_ms", duration.Milliseconds()),
		attribute.Float64("response.duration_seconds", duration.Seconds()),
		attribute.Int("response.message_length", len(response.Message)),
	)
	span.SetStatus(codes.Ok, "Request processed successfully")

	return response, nil
}

func (s *microServiceImpl) GetWeather(ctx context.Context, req *pb.WeatherRequest) (*pb.WeatherResponse, error) {
	startTime := time.Now()
	tracer := otel.Tracer("micro-2")
	ctx, span := tracer.Start(ctx, "micro-2: GetWeather",
		trace.WithAttributes(
			attribute.String("rpc.system", "grpc"),
			attribute.String("rpc.service", "micro.MicroService"),
			attribute.String("rpc.method", "GetWeather"),
			attribute.String("weather.city", req.City),
		),
	)
	defer span.End()

	spanContext := span.SpanContext()
	traceID := spanContext.TraceID().String()
	spanID := spanContext.SpanID().String()

	weatherData, err := s.weatherService.GetWeather(ctx, req.City)

	duration := time.Since(startTime)
	span.SetAttributes(attribute.Int64("response.duration_ms", duration.Milliseconds()))

	if err != nil {
		span.SetAttributes(attribute.Bool("response.success", false))
		span.SetStatus(codes.Error, err.Error())
		span.RecordError(err)

		logWithContext(ctx, "error", fmt.Sprintf("Failed to get weather for %s", req.City), map[string]interface{}{
			"trace_id": traceID,
			"span_id":  spanID,
			"error":    err.Error(),
		})

		return nil, fmt.Errorf("failed to get weather: %v", err)
	}

	response := &pb.WeatherResponse{
		City:        req.City,
		Temperature: weatherData.Temperature,
		Condition:   weatherData.Condition,
		Humidity:    weatherData.Humidity,
		WindSpeed:   weatherData.WindSpeed,
		Source:      "openweathermap",
	}

	span.SetAttributes(
		attribute.Bool("response.success", true),
		attribute.Float64("weather.temperature", weatherData.Temperature),
		attribute.Int("weather.humidity", int(weatherData.Humidity)),
	)
	span.SetStatus(codes.Ok, "Weather retrieved successfully")

	logWithContext(ctx, "info", fmt.Sprintf("Weather retrieved successfully for %s", req.City), map[string]interface{}{
		"trace_id": traceID,
		"span_id":  spanID,
	})

	return response, nil
}

func (s *microServiceImpl) SaveWeatherData(ctx context.Context, req *pb.WeatherDataRequest) (*pb.WeatherDataResponse, error) {
	startTime := time.Now()
	tracer := otel.Tracer("micro-2")
	ctx, span := tracer.Start(ctx, "micro-2: SaveWeatherData",
		trace.WithAttributes(
			attribute.String("rpc.system", "grpc"),
			attribute.String("rpc.service", "micro.MicroService"),
			attribute.String("rpc.method", "SaveWeatherData"),
			attribute.String("weather.city", req.City),
			attribute.Float64("weather.temperature", req.Temperature),
		),
	)
	defer span.End()

	spanContext := span.SpanContext()
	traceID := spanContext.TraceID().String()
	spanID := spanContext.SpanID().String()

	id, err := s.db.SaveWeatherData(ctx, req.City, req.Temperature, req.Condition, req.Humidity, req.WindSpeed)

	duration := time.Since(startTime)
	span.SetAttributes(attribute.Int64("response.duration_ms", duration.Milliseconds()))

	if err != nil {
		span.SetAttributes(attribute.Bool("response.success", false))
		span.SetStatus(codes.Error, err.Error())
		span.RecordError(err)

		logWithContext(ctx, "error", "Failed to save weather data", map[string]interface{}{
			"trace_id": traceID,
			"span_id":  spanID,
			"error":    err.Error(),
		})

		return nil, fmt.Errorf("failed to save weather data: %v", err)
	}

	response := &pb.WeatherDataResponse{
		Id:      id,
		Message: "Weather data saved successfully",
	}

	span.SetAttributes(
		attribute.Bool("response.success", true),
		attribute.Int("db.record.id", int(id)),
	)
	span.SetStatus(codes.Ok, "Weather data saved successfully")

	logWithContext(ctx, "info", fmt.Sprintf("Weather data saved successfully with id %d", id), map[string]interface{}{
		"trace_id": traceID,
		"span_id":  spanID,
	})

	return response, nil
}

func (s *microServiceImpl) GetWeatherHistory(ctx context.Context, req *pb.WeatherHistoryRequest) (*pb.WeatherHistoryResponse, error) {
	startTime := time.Now()
	tracer := otel.Tracer("micro-2")

	attrs := []attribute.KeyValue{
		attribute.String("rpc.system", "grpc"),
		attribute.String("rpc.service", "micro.MicroService"),
		attribute.String("rpc.method", "GetWeatherHistory"),
		attribute.Int("query.limit", int(req.Limit)),
	}
	if req.City != "" {
		attrs = append(attrs, attribute.String("weather.city", req.City))
	}

	ctx, span := tracer.Start(ctx, "micro-2: GetWeatherHistory", trace.WithAttributes(attrs...))
	defer span.End()

	spanContext := span.SpanContext()
	traceID := spanContext.TraceID().String()
	spanID := spanContext.SpanID().String()

	city := req.City
	if city == "" {
		city = "all cities"
	}

	limit := req.Limit
	if limit <= 0 {
		limit = 10
	}

	records, err := s.db.GetWeatherHistory(ctx, req.City, limit)

	duration := time.Since(startTime)
	span.SetAttributes(attribute.Int64("response.duration_ms", duration.Milliseconds()))

	if err != nil {
		span.SetAttributes(attribute.Bool("response.success", false))
		span.SetStatus(codes.Error, err.Error())
		span.RecordError(err)

		logWithContext(ctx, "error", "Failed to get weather history", map[string]interface{}{
			"trace_id": traceID,
			"span_id":  spanID,
			"error":    err.Error(),
		})

		return nil, fmt.Errorf("failed to get weather history: %v", err)
	}

	protoRecords := make([]*pb.WeatherRecord, 0, len(records))
	for _, r := range records {
		humidity := int32(0)
		if r.Humidity != nil {
			humidity = *r.Humidity
		}
		windSpeed := 0.0
		if r.WindSpeed != nil {
			windSpeed = *r.WindSpeed
		}

		protoRecords = append(protoRecords, &pb.WeatherRecord{
			Id:          r.ID,
			City:        r.City,
			Temperature: r.Temperature,
			Condition:   r.Condition,
			Humidity:    humidity,
			WindSpeed:   windSpeed,
			Timestamp:   r.Timestamp.Format(time.RFC3339),
		})
	}

	response := &pb.WeatherHistoryResponse{
		Records: protoRecords,
		City:    city,
		Count:   int32(len(protoRecords)),
	}

	span.SetAttributes(
		attribute.Bool("response.success", true),
		attribute.Int("db.result.count", len(protoRecords)),
	)
	span.SetStatus(codes.Ok, fmt.Sprintf("Retrieved %d records", len(protoRecords)))

	logWithContext(ctx, "info", fmt.Sprintf("Retrieved %d weather records for %s", len(protoRecords), city), map[string]interface{}{
		"trace_id": traceID,
		"span_id":  spanID,
	})

	return response, nil
}

func logWithContext(ctx context.Context, level string, message string, fields map[string]interface{}) {
	if config.MainLoggerProvider == nil {
		log.Printf("LoggerProvider not configured, falling back to standard log")
		log.Printf("%s: %s", level, message)
		return
	}

	logger := config.MainLoggerProvider.Logger("micro-2")

	span := trace.SpanFromContext(ctx)
	spanContext := span.SpanContext()

	var severity otellog.Severity
	switch level {
	case "error":
		severity = otellog.SeverityError
	case "warn":
		severity = otellog.SeverityWarn
	default:
		severity = otellog.SeverityInfo
	}

	attrs := make([]otellog.KeyValue, 0)

	if spanContext.IsValid() {
		attrs = append(attrs,
			otellog.String("trace.id", spanContext.TraceID().String()),
			otellog.String("span.id", spanContext.SpanID().String()),
			otellog.String("trace.flags", spanContext.TraceFlags().String()),
		)
	}

	if fields != nil {
		for k, v := range fields {
			switch val := v.(type) {
			case string:
				attrs = append(attrs, otellog.String(k, val))
			case int:
				attrs = append(attrs, otellog.Int(k, val))
			case int64:
				attrs = append(attrs, otellog.Int64(k, val))
			case float64:
				attrs = append(attrs, otellog.Float64(k, val))
			case bool:
				attrs = append(attrs, otellog.Bool(k, val))
			default:
				attrs = append(attrs, otellog.String(k, fmt.Sprintf("%v", val)))
			}
		}
	}

	var record otellog.Record
	record.SetTimestamp(time.Now())
	record.SetSeverity(severity)
	record.SetSeverityText(strings.ToUpper(level))
	record.SetBody(otellog.StringValue(message))
	record.AddAttributes(attrs...)

	logger.Emit(ctx, record)
}

type gRPCMetadataCarrier struct {
	md metadata.MD
}

var _ propagation.TextMapCarrier = gRPCMetadataCarrier{}

func (c gRPCMetadataCarrier) Get(key string) string {
	values := c.md.Get(key)
	if len(values) == 0 {
		return ""
	}
	return values[0]
}

func (c gRPCMetadataCarrier) Set(key, value string) {
	c.md.Set(key, value)
}

func (c gRPCMetadataCarrier) Keys() []string {
	keys := make([]string, 0, len(c.md))
	for k := range c.md {
		keys = append(keys, k)
	}
	return keys
}

func tracingUnaryInterceptor(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
	md, ok := metadata.FromIncomingContext(ctx)
	if ok {
		carrier := gRPCMetadataCarrier{md: md}
		ctx = otel.GetTextMapPropagator().Extract(ctx, carrier)
	}

	return handler(ctx, req)
}

func startGRPCServer() error {
	dbHost := getEnvOrDefault("DB_HOST", "postgres")
	dbPort := getEnvOrDefault("DB_PORT", "5432")
	dbUser := getEnvOrDefault("DB_USER", "postgres")
	dbPassword := getEnvOrDefault("DB_PASSWORD", "postgres123")
	dbName := getEnvOrDefault("DB_NAME", "observability")

	database, err := db.NewDatabase(dbHost, dbPort, dbUser, dbPassword, dbName)
	if err != nil {
		logWithContext(context.Background(), "error", "Failed to connect to database", map[string]interface{}{
			"error": err.Error(),
		})
		return fmt.Errorf("failed to connect to database: %v", err)
	}
	defer database.Close()

	apiKey := getEnvRequired("WEATHER_API_KEY")
	weatherService := weather.NewWeatherService(apiKey)

	lis, err := net.Listen("tcp", ":50051")
	if err != nil {
		return fmt.Errorf("failed to listen on port 50051: %v", err)
	}

	s := grpc.NewServer(
		grpc.UnaryInterceptor(tracingUnaryInterceptor),
	)

	pb.RegisterMicroServiceServer(s, &microServiceImpl{
		counter:        0,
		weatherService: weatherService,
		db:             database,
	})

	reflection.Register(s)

	logWithContext(context.Background(), "info", "gRPC server listening on port 50051", nil)

	return s.Serve(lis)
}

func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvRequired(key string) string {
	value := os.Getenv(key)
	if value == "" {
		log.Fatalf("Error: La variable de entorno %s es requerida pero no está definida", key)
	}
	return value
}
