package config

import (
	"context"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploghttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/log"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

var (
	MainTracerProvider    *sdktrace.TracerProvider
	WeatherTracerProvider *sdktrace.TracerProvider
	DBTracerProvider      *sdktrace.TracerProvider
	MainLoggerProvider    *log.LoggerProvider
)

func InitTracer() (*sdktrace.TracerProvider, error) {
	exporter, err := otlptracegrpc.New(
		context.Background(),
		otlptracegrpc.WithEndpoint("otel-collector:4317"),
		otlptracegrpc.WithDialOption(grpc.WithTransportCredentials(insecure.NewCredentials())),
	)
	if err != nil {
		return nil, err
	}

	MainTracerProvider = sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(resource.NewSchemaless(
			attribute.String("service.name", "micro-2"),
			attribute.String("service.version", "1.0.0"),
			attribute.String("service.language", "go"),
			attribute.String("telemetry.sdk.name", "opentelemetry"),
			attribute.String("telemetry.sdk.language", "go"),
			attribute.String("telemetry.sdk.version", "1.38.0"),
			attribute.String("application", "lab-observability"),
		)),
	)

	WeatherTracerProvider = sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(resource.NewSchemaless(
			attribute.String("service.name", "openweathermap-api"),
			attribute.String("service.version", "2.5"),
			attribute.String("application", "lab-observability"),
		)),
	)

	DBTracerProvider = sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(resource.NewSchemaless(
			attribute.String("service.name", "postgres"),
			attribute.String("db.system", "postgresql"),
			attribute.String("application", "lab-observability"),
		)),
	)

	otel.SetTracerProvider(MainTracerProvider)

	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	return MainTracerProvider, nil
}

func InitLogger() (*log.LoggerProvider, error) {
	exporter, err := otlploghttp.New(
		context.Background(),
		otlploghttp.WithEndpoint("otel-collector:4318"),
		otlploghttp.WithURLPath("/v1/logs"),
		otlploghttp.WithInsecure(),
	)
	if err != nil {
		return nil, err
	}

	MainLoggerProvider = log.NewLoggerProvider(
		log.WithProcessor(log.NewBatchProcessor(exporter)),
		log.WithResource(resource.NewSchemaless(
			attribute.String("service.name", "micro-2"),
			attribute.String("service.version", "1.0.0"),
			attribute.String("service.language", "go"),
			attribute.String("application", "lab-observability"),
		)),
	)

	return MainLoggerProvider, nil
}
