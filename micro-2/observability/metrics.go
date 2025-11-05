package observability

import (
	"context"
	"log"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
)

type MetricsHandler struct {
	EventCounter  metric.Int64Counter
	EventDuration metric.Float64Histogram
}

func NewMetricsHandler() *MetricsHandler {
	meter := otel.Meter("micro-2")

	eventCounter, err := meter.Int64Counter("events_generated_total")
	if err != nil {
		log.Printf("Error creating eventCounter: %v", err)
	}

	eventDuration, err := meter.Float64Histogram("event_duration_seconds")
	if err != nil {
		log.Printf("Error creating eventDuration: %v", err)
	}

	return &MetricsHandler{
		EventCounter:  eventCounter,
		EventDuration: eventDuration,
	}
}

func (m *MetricsHandler) RecordEvent(ctx context.Context, eventType string) {
	m.EventCounter.Add(ctx, 1, metric.WithAttributes(attribute.String("event_type", eventType)))
}

func (m *MetricsHandler) RecordEventDuration(ctx context.Context, duration float64, eventType string) {
	m.EventDuration.Record(ctx, duration, metric.WithAttributes(attribute.String("event_type", eventType)))
}
