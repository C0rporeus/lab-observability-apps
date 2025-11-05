package service

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"time"

	"micro-2/observability"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

type EventService struct {
	metrics      *observability.MetricsHandler
	eventCounter int64
}

func NewEventService(metrics *observability.MetricsHandler) *EventService {
	return &EventService{
		metrics:      metrics,
		eventCounter: 0,
	}
}

func (s *EventService) SimulateEvent(ctx context.Context, tracer trace.Tracer) error {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("Recovered in SimulateEvent: %v", r)
		}
	}()

	ctx, span := tracer.Start(ctx, "simulateEvent")
	defer span.End()

	startTime := time.Now()
	s.eventCounter++

	span.SetAttributes(
		attribute.Int64("event.counter", s.eventCounter),
		attribute.String("event.type", "simulated"),
	)

	log.Printf("Generating simulated event #%d...", s.eventCounter)

	processingTime := time.Duration(rand.Intn(3000)+1000) * time.Millisecond

	if rand.Float32() < 0.05 {
		span.SetStatus(codes.Error, "Simulated error")
		span.SetAttributes(attribute.Bool("event.error", true))
		log.Printf("Simulating error for event #%d", s.eventCounter)
		time.Sleep(500 * time.Millisecond)
		return fmt.Errorf("simulated processing error for event #%d", s.eventCounter)
	}

	time.Sleep(processingTime)

	duration := time.Since(startTime).Seconds()

	func() {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("Error recording metrics: %v", r)
			}
		}()

		s.metrics.RecordEventDuration(ctx, duration, "simulated")
		s.metrics.RecordEvent(ctx, "simulated")
	}()

	span.SetAttributes(
		attribute.Float64("event.duration_seconds", duration),
		attribute.Bool("event.error", false),
	)

	log.Printf("Simulated event #%d registered successfully (duration: %.2fs)", s.eventCounter, duration)
	return nil
}

func (s *EventService) GetEventStats() map[string]interface{} {
	return map[string]interface{}{
		"total_events": s.eventCounter,
		"status":       "healthy",
	}
}
