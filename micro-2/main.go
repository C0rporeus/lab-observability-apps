package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
	"google.golang.org/grpc"
)

func initTracer() (*sdktrace.TracerProvider, error) {
	// Configurar exportador OTLP gRPC
	exporter, err := otlptracegrpc.New(
		context.Background(),
		otlptracegrpc.WithEndpoint("otel-collector:4317"),
		otlptracegrpc.WithDialOption(grpc.WithInsecure()),
	)
	if err != nil {
		return nil, err
	}

	// Crear proveedor de trazas
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(resource.NewSchemaless(
			attribute.String("service.name", "micro-2"),
		)),
	)
	otel.SetTracerProvider(tp)
	return tp, nil
}

func main() {
	tp, err := initTracer()
	if err != nil {
		log.Fatalf("Error al inicializar el tracer: %v", err)
	}
	defer func() { _ = tp.Shutdown(context.Background()) }()

	// Crear un tracer y un contexto
	tracer := otel.Tracer("micro-2-tracer")
	ctx, span := tracer.Start(context.Background(), "main-operation")
	defer span.End()

	// Simulación de evento
	simulateEvent(ctx, tracer)

	log.Println("Aplicación corriendo. Presione Ctrl+C para detener.")
	select {} // Mantener la aplicación en ejecución
}

func simulateEvent(ctx context.Context, tracer trace.Tracer) {
	_, span := tracer.Start(ctx, "simulateEvent")
	defer span.End()

	log.Println("Generando evento simulado ...")
	time.Sleep(2 * time.Second)
	fmt.Println("Evento simulado registrado en Jaeger")
}
