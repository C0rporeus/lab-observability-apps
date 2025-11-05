package weather

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"micro-2/config"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

type WeatherData struct {
	Temperature float64
	Condition   string
	Humidity    int32
	WindSpeed   float64
}

type WeatherService struct {
	client  *http.Client
	apiKey  string
	baseURL string
}

func NewWeatherService(apiKey string) *WeatherService {
	// Configure TLS to skip verification (for Linkerd mTLS proxy)
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{
			InsecureSkipVerify: true,
		},
	}

	return &WeatherService{
		client: &http.Client{
			Timeout:   10 * time.Second,
			Transport: tr,
		},
		apiKey:  apiKey,
		baseURL: "https://api.openweathermap.org/data/2.5",
	}
}

func (w *WeatherService) GetWeather(ctx context.Context, city string) (*WeatherData, error) {
	tracer := config.WeatherTracerProvider.Tracer("openweathermap-api")
	ctx, span := tracer.Start(ctx, "http.get.weather",
		trace.WithAttributes(
			attribute.String("http.method", "GET"),
			attribute.String("http.route", "/weather"),
		),
	)
	defer span.End()

	url := fmt.Sprintf("%s/weather?q=%s&appid=%s&units=metric", w.baseURL, city, w.apiKey)
	span.SetAttributes(attribute.String("http.url", url))

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		span.SetStatus(codes.Error, err.Error())
		span.RecordError(err)
		return nil, err
	}

	resp, err := w.client.Do(req)
	if err != nil {
		span.SetAttributes(attribute.Int("http.status_code", 0))
		span.SetStatus(codes.Error, err.Error())
		span.RecordError(err)
		return nil, err
	}
	defer resp.Body.Close()

	span.SetAttributes(
		attribute.Int("http.status_code", resp.StatusCode),
		attribute.String("http.flavor", "1.1"),
	)

	if resp.StatusCode != http.StatusOK {
		err := fmt.Errorf("HTTP error: %d", resp.StatusCode)
		span.SetStatus(codes.Error, err.Error())
		span.RecordError(err)
		return nil, err
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		span.SetStatus(codes.Error, err.Error())
		span.RecordError(err)
		return nil, err
	}

	span.SetAttributes(attribute.Int("http.response.size", len(body)))

	var apiResponse struct {
		Main struct {
			Temp     float64 `json:"temp"`
			Humidity int32   `json:"humidity"`
		} `json:"main"`
		Weather []struct {
			Main        string `json:"main"`
			Description string `json:"description"`
		} `json:"weather"`
		Wind struct {
			Speed float64 `json:"speed"`
		} `json:"wind"`
	}

	if err := json.Unmarshal(body, &apiResponse); err != nil {
		span.SetStatus(codes.Error, err.Error())
		span.RecordError(err)
		return nil, err
	}

	condition := "unknown"
	if len(apiResponse.Weather) > 0 {
		condition = apiResponse.Weather[0].Description
	}

	data := &WeatherData{
		Temperature: apiResponse.Main.Temp,
		Condition:   condition,
		Humidity:    apiResponse.Main.Humidity,
		WindSpeed:   apiResponse.Wind.Speed,
	}

	span.SetStatus(codes.Ok, "Weather retrieved successfully")

	return data, nil
}
