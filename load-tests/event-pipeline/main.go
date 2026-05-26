package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"math"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/segmentio/kafka-go"
)

type config struct {
	Mode            string
	Requests        int
	Concurrency     int
	Consumers       int
	Brokers         []string
	TopicPrefix     string
	Topic           string
	HandlerWork     time.Duration
	ConsumerWarmup  time.Duration
	ConsumerTimeout time.Duration
	RunID           string
	JSONPath        string
	ReportPath      string
}

type reportConfig struct {
	Mode            string   `json:"mode"`
	Requests        int      `json:"requests"`
	Concurrency     int      `json:"concurrency"`
	Consumers       int      `json:"consumers"`
	Brokers         []string `json:"brokers"`
	Topic           string   `json:"topic"`
	HandlerWork     string   `json:"handler_work"`
	ConsumerWarmup  string   `json:"consumer_warmup"`
	ConsumerTimeout string   `json:"consumer_timeout"`
	RunID           string   `json:"run_id"`
}

type report struct {
	GeneratedAt string       `json:"generated_at"`
	Config      reportConfig `json:"config"`
	Results     []runResult  `json:"results"`
}

type runResult struct {
	Mode             string  `json:"mode"`
	StartedAt        string  `json:"started_at"`
	FinishedAt       string  `json:"finished_at"`
	DurationMs       float64 `json:"duration_ms"`
	Requests         int     `json:"requests"`
	Success          int     `json:"success"`
	Failed           int     `json:"failed"`
	ThroughputOpsSec float64 `json:"throughput_ops_sec"`

	OperationLatency *stats `json:"operation_latency_ms,omitempty"`
	PublishLatency   *stats `json:"publish_latency_ms,omitempty"`
	DeliveryLag      *stats `json:"delivery_lag_ms,omitempty"`
	HandlerLatency   *stats `json:"handler_latency_ms,omitempty"`

	Errors []string `json:"errors,omitempty"`
}

type stats struct {
	Count int     `json:"count"`
	Min   float64 `json:"min"`
	Mean  float64 `json:"mean"`
	P50   float64 `json:"p50"`
	P90   float64 `json:"p90"`
	P95   float64 `json:"p95"`
	P99   float64 `json:"p99"`
	Max   float64 `json:"max"`
}

type loadEvent struct {
	RunID              string         `json:"run_id"`
	Sequence           int            `json:"sequence"`
	EventType          string         `json:"event_type"`
	OrderID            string         `json:"order_id"`
	CustomerID         string         `json:"customer_id"`
	MasterID           string         `json:"master_id"`
	Title              string         `json:"title"`
	Price              int            `json:"price"`
	ProducedAt         string         `json:"produced_at"`
	ProducedAtUnixNano int64          `json:"produced_at_unix_nano"`
	Payload            map[string]any `json:"payload"`
}

type notificationEnvelope struct {
	Type     string         `json:"type"`
	Title    string         `json:"title"`
	Body     string         `json:"body"`
	Channels []string       `json:"channels"`
	Data     map[string]any `json:"data"`
}

func main() {
	cfg, err := parseFlags()
	if err != nil {
		fatal(err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	results := make([]runResult, 0, 2)
	switch cfg.Mode {
	case "sync":
		results = append(results, runSync(ctx, cfg))
	case "kafka":
		results = append(results, runKafka(ctx, cfg))
	case "both":
		results = append(results, runSync(ctx, cfg))
		results = append(results, runKafka(ctx, cfg))
	default:
		fatal(fmt.Errorf("unknown mode %q: use sync, kafka, or both", cfg.Mode))
	}

	rep := report{
		GeneratedAt: time.Now().Format(time.RFC3339),
		Config: reportConfig{
			Mode:            cfg.Mode,
			Requests:        cfg.Requests,
			Concurrency:     cfg.Concurrency,
			Consumers:       cfg.Consumers,
			Brokers:         cfg.Brokers,
			Topic:           cfg.Topic,
			HandlerWork:     cfg.HandlerWork.String(),
			ConsumerWarmup:  cfg.ConsumerWarmup.String(),
			ConsumerTimeout: cfg.ConsumerTimeout.String(),
			RunID:           cfg.RunID,
		},
		Results: results,
	}

	if err := writeJSON(cfg.JSONPath, rep); err != nil {
		fatal(err)
	}
	if err := writeMarkdown(cfg.ReportPath, rep); err != nil {
		fatal(err)
	}

	printSummary(rep, cfg.JSONPath, cfg.ReportPath)
}

func parseFlags() (config, error) {
	var brokers string
	var cfg config

	flag.StringVar(&cfg.Mode, "mode", "both", "test mode: sync, kafka, or both")
	flag.IntVar(&cfg.Requests, "requests", 1000, "number of events to process")
	flag.IntVar(&cfg.Concurrency, "concurrency", 50, "parallel producer workers")
	flag.IntVar(&cfg.Consumers, "consumers", 4, "Kafka consumer workers")
	flag.StringVar(&brokers, "kafka-brokers", "localhost:29092", "comma-separated Kafka broker addresses")
	flag.StringVar(&cfg.TopicPrefix, "topic-prefix", "load.events", "Kafka topic prefix; the run id is appended")
	flag.DurationVar(&cfg.HandlerWork, "handler-work", 0, "optional artificial handler work, for example 2ms")
	flag.DurationVar(&cfg.ConsumerWarmup, "consumer-warmup", 1500*time.Millisecond, "time to let Kafka consumers join the group before producing")
	flag.DurationVar(&cfg.ConsumerTimeout, "consumer-timeout", 60*time.Second, "max time to wait for Kafka delivery after producers finish")
	flag.StringVar(&cfg.RunID, "run-id", "", "stable run id; generated when empty")
	flag.StringVar(&cfg.JSONPath, "json", "", "path for machine-readable JSON results")
	flag.StringVar(&cfg.ReportPath, "report", "", "path for Markdown report")
	flag.Parse()

	cfg.Mode = strings.ToLower(strings.TrimSpace(cfg.Mode))
	cfg.Brokers = splitCSV(brokers)
	if len(cfg.Brokers) == 0 {
		return cfg, errors.New("at least one Kafka broker is required")
	}
	if cfg.Requests <= 0 {
		return cfg, errors.New("requests must be greater than zero")
	}
	if cfg.Concurrency <= 0 {
		return cfg, errors.New("concurrency must be greater than zero")
	}
	if cfg.Consumers <= 0 {
		return cfg, errors.New("consumers must be greater than zero")
	}
	if cfg.RunID == "" {
		cfg.RunID = "load-" + time.Now().Format("20060102-150405") + "-" + randomHex(4)
	}
	cfg.Topic = sanitizeTopic(cfg.TopicPrefix + "." + cfg.RunID)

	if cfg.JSONPath == "" {
		cfg.JSONPath = filepath.Join("..", "results", "event-pipeline-"+cfg.RunID+".json")
	}
	if cfg.ReportPath == "" {
		cfg.ReportPath = filepath.Join("..", "results", "event-pipeline-"+cfg.RunID+".md")
	}

	return cfg, nil
}

func runSync(ctx context.Context, cfg config) runResult {
	started := time.Now()
	operationLatencies := make([]float64, cfg.Requests)
	handlerLatencies := make([]float64, cfg.Requests)
	var failed atomic.Int64
	errs := newErrorCollector(5)

	jobs := make(chan int)
	var wg sync.WaitGroup
	for worker := 0; worker < cfg.Concurrency; worker++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for seq := range jobs {
				select {
				case <-ctx.Done():
					failed.Add(1)
					errs.add(ctx.Err())
					continue
				default:
				}

				opStarted := time.Now()
				value, err := buildEventJSON(cfg.RunID, seq)
				if err == nil {
					var handler time.Duration
					handler, err = processEvent(value, cfg.HandlerWork)
					handlerLatencies[seq] = millis(handler)
				}
				operationLatencies[seq] = millis(time.Since(opStarted))
				if err != nil {
					failed.Add(1)
					errs.add(err)
				}
			}
		}()
	}

	for seq := 0; seq < cfg.Requests; seq++ {
		jobs <- seq
	}
	close(jobs)
	wg.Wait()

	return finalizeResult("sync", started, cfg.Requests, int(failed.Load()), operationLatencies, nil, nil, handlerLatencies, errs.values())
}

func runKafka(ctx context.Context, cfg config) runResult {
	setupStarted := time.Now()
	errs := newErrorCollector(8)
	publishLatencies := make([]float64, cfg.Requests)
	deliveryLags := make([]float64, cfg.Requests)
	handlerLatencies := make([]float64, cfg.Requests)
	processedSeq := make([]atomic.Bool, cfg.Requests)

	if err := ensureTopic(ctx, cfg.Brokers[0], cfg.Topic, max(cfg.Consumers, 1)); err != nil {
		errs.add(fmt.Errorf("create Kafka topic %s: %w", cfg.Topic, err))
		return finalizeResult("kafka", setupStarted, cfg.Requests, cfg.Requests, nil, publishLatencies, deliveryLags, handlerLatencies, errs.values())
	}

	consumerCtx, cancelConsumers := context.WithCancel(ctx)
	defer cancelConsumers()

	var processed atomic.Int64
	var consumerWG sync.WaitGroup
	for i := 0; i < cfg.Consumers; i++ {
		consumerWG.Add(1)
		go func(idx int) {
			defer consumerWG.Done()
			reader := kafka.NewReader(kafka.ReaderConfig{
				Brokers:     cfg.Brokers,
				Topic:       cfg.Topic,
				Partition:   idx,
				MinBytes:    1,
				MaxBytes:    10e6,
				MaxWait:     100 * time.Millisecond,
				StartOffset: kafka.FirstOffset,
			})
			defer func() {
				if err := reader.Close(); err != nil {
					errs.add(fmt.Errorf("close consumer %d: %w", idx, err))
				}
			}()

			for {
				if processed.Load() >= int64(cfg.Requests) {
					return
				}

				msg, err := reader.FetchMessage(consumerCtx)
				if err != nil {
					if consumerCtx.Err() != nil {
						return
					}
					errs.add(fmt.Errorf("consumer %d fetch: %w", idx, err))
					continue
				}

				evt, err := decodeEvent(msg.Value)
				if err != nil {
					errs.add(fmt.Errorf("consumer %d decode: %w", idx, err))
					continue
				}
				if evt.RunID != cfg.RunID {
					continue
				}

				handlerDuration, err := processEvent(msg.Value, cfg.HandlerWork)
				if err != nil {
					errs.add(fmt.Errorf("consumer %d process seq %d: %w", idx, evt.Sequence, err))
					continue
				}

				if evt.Sequence >= 0 && evt.Sequence < cfg.Requests && processedSeq[evt.Sequence].CompareAndSwap(false, true) {
					deliveryLags[evt.Sequence] = millis(time.Since(time.Unix(0, evt.ProducedAtUnixNano)))
					handlerLatencies[evt.Sequence] = millis(handlerDuration)
					processed.Add(1)
				}
			}
		}(i)
	}

	time.Sleep(cfg.ConsumerWarmup)
	started := time.Now()

	var published atomic.Int64
	var publishFailed atomic.Int64
	writer := &kafka.Writer{
		Addr:         kafka.TCP(cfg.Brokers...),
		Topic:        cfg.Topic,
		Balancer:     &kafka.LeastBytes{},
		RequiredAcks: kafka.RequireAll,
		Async:        false,
		BatchTimeout: 10 * time.Millisecond,
	}

	jobs := make(chan int)
	var producerWG sync.WaitGroup
	for worker := 0; worker < cfg.Concurrency; worker++ {
		producerWG.Add(1)
		go func() {
			defer producerWG.Done()
			for seq := range jobs {
				value, err := buildEventJSON(cfg.RunID, seq)
				if err != nil {
					publishFailed.Add(1)
					errs.add(err)
					continue
				}

				writeStarted := time.Now()
				err = writer.WriteMessages(ctx, kafka.Message{
					Key:   []byte(strconv.Itoa(seq)),
					Value: value,
					Time:  time.Now(),
				})
				publishLatencies[seq] = millis(time.Since(writeStarted))
				if err != nil {
					publishFailed.Add(1)
					errs.add(fmt.Errorf("publish seq %d: %w", seq, err))
					continue
				}
				published.Add(1)
			}
		}()
	}

	for seq := 0; seq < cfg.Requests; seq++ {
		jobs <- seq
	}
	close(jobs)
	producerWG.Wait()
	if err := writer.Close(); err != nil {
		errs.add(fmt.Errorf("close producer: %w", err))
	}

	deadline := time.NewTimer(cfg.ConsumerTimeout)
	ticker := time.NewTicker(100 * time.Millisecond)
	for processed.Load() < published.Load() {
		select {
		case <-ctx.Done():
			errs.add(ctx.Err())
			finished := time.Now()
			deadline.Stop()
			ticker.Stop()
			cancelConsumers()
			consumerWG.Wait()
			return finalizeResultAt("kafka", started, finished, cfg.Requests, cfg.Requests-int(processed.Load()), nil, publishLatencies, deliveryLags, handlerLatencies, errs.values())
		case <-deadline.C:
			errs.add(fmt.Errorf("timed out waiting for Kafka delivery: processed %d of %d published", processed.Load(), published.Load()))
			finished := time.Now()
			ticker.Stop()
			cancelConsumers()
			consumerWG.Wait()
			return finalizeResultAt("kafka", started, finished, cfg.Requests, cfg.Requests-int(processed.Load()), nil, publishLatencies, deliveryLags, handlerLatencies, errs.values())
		case <-ticker.C:
		}
	}
	finished := time.Now()
	deadline.Stop()
	ticker.Stop()
	cancelConsumers()
	consumerWG.Wait()

	failed := int(publishFailed.Load()) + (int(published.Load()) - int(processed.Load()))
	return finalizeResultAt("kafka", started, finished, cfg.Requests, failed, nil, publishLatencies, deliveryLags, handlerLatencies, errs.values())
}

func finalizeResult(mode string, started time.Time, requests, failed int, operation, publish, delivery, handler []float64, errs []string) runResult {
	return finalizeResultAt(mode, started, time.Now(), requests, failed, operation, publish, delivery, handler, errs)
}

func finalizeResultAt(mode string, started, finished time.Time, requests, failed int, operation, publish, delivery, handler []float64, errs []string) runResult {
	success := requests - failed
	if success < 0 {
		success = 0
	}
	duration := finished.Sub(started)
	result := runResult{
		Mode:             mode,
		StartedAt:        started.Format(time.RFC3339),
		FinishedAt:       finished.Format(time.RFC3339),
		DurationMs:       millis(duration),
		Requests:         requests,
		Success:          success,
		Failed:           failed,
		ThroughputOpsSec: float64(success) / duration.Seconds(),
		Errors:           errs,
	}

	if operation != nil {
		result.OperationLatency = statsFrom(operation)
	}
	if publish != nil {
		result.PublishLatency = statsFrom(nonZero(publish))
	}
	if delivery != nil {
		result.DeliveryLag = statsFrom(nonZero(delivery))
	}
	if handler != nil {
		result.HandlerLatency = statsFrom(nonZero(handler))
	}

	return result
}

func buildEventJSON(runID string, seq int) ([]byte, error) {
	now := time.Now().UTC()
	evt := loadEvent{
		RunID:              runID,
		Sequence:           seq,
		EventType:          "order.created",
		OrderID:            uuidV4(),
		CustomerID:         uuidV4(),
		MasterID:           uuidV4(),
		Title:              fmt.Sprintf("Load test order #%d", seq+1),
		Price:              1500 + (seq % 10 * 250),
		ProducedAt:         now.Format(time.RFC3339Nano),
		ProducedAtUnixNano: now.UnixNano(),
		Payload: map[string]any{
			"category": "load-test",
			"city":     "Yakutsk",
			"currency": "RUB",
		},
	}
	return json.Marshal(evt)
}

func decodeEvent(value []byte) (loadEvent, error) {
	var evt loadEvent
	if err := json.Unmarshal(value, &evt); err != nil {
		return evt, err
	}
	return evt, nil
}

func processEvent(value []byte, handlerWork time.Duration) (time.Duration, error) {
	started := time.Now()
	evt, err := decodeEvent(value)
	if err != nil {
		return 0, err
	}
	if evt.RunID == "" || evt.EventType == "" || evt.OrderID == "" || evt.CustomerID == "" {
		return 0, errors.New("invalid load event: required fields are empty")
	}

	notification := notificationEnvelope{
		Type:     "order_created",
		Title:    "New order created",
		Body:     fmt.Sprintf("Order %s is ready for matching", evt.OrderID),
		Channels: []string{"websocket", "email"},
		Data: map[string]any{
			"run_id":      evt.RunID,
			"sequence":    evt.Sequence,
			"event_type":  evt.EventType,
			"order_id":    evt.OrderID,
			"customer_id": evt.CustomerID,
			"master_id":   evt.MasterID,
			"title":       evt.Title,
			"price":       evt.Price,
		},
	}
	if _, err := json.Marshal(notification); err != nil {
		return 0, err
	}
	if handlerWork > 0 {
		time.Sleep(handlerWork)
	}
	return time.Since(started), nil
}

func ensureTopic(ctx context.Context, broker, topic string, partitions int) error {
	dialer := kafka.Dialer{Timeout: 10 * time.Second}
	conn, err := dialer.DialContext(ctx, "tcp", broker)
	if err != nil {
		return err
	}
	defer conn.Close()

	controller, err := conn.Controller()
	if err != nil {
		return err
	}

	controllerAddr := net.JoinHostPort(controller.Host, strconv.Itoa(controller.Port))
	controllerConn, err := dialer.DialContext(ctx, "tcp", controllerAddr)
	if err != nil {
		return err
	}
	defer controllerConn.Close()

	err = controllerConn.CreateTopics(kafka.TopicConfig{
		Topic:             topic,
		NumPartitions:     partitions,
		ReplicationFactor: 1,
	})
	if err != nil && !strings.Contains(strings.ToLower(err.Error()), "already exists") {
		return err
	}
	return nil
}

func statsFrom(values []float64) *stats {
	if len(values) == 0 {
		return nil
	}
	cp := append([]float64(nil), values...)
	sort.Float64s(cp)
	var sum float64
	for _, v := range cp {
		sum += v
	}
	return &stats{
		Count: len(cp),
		Min:   round(cp[0]),
		Mean:  round(sum / float64(len(cp))),
		P50:   round(percentile(cp, 50)),
		P90:   round(percentile(cp, 90)),
		P95:   round(percentile(cp, 95)),
		P99:   round(percentile(cp, 99)),
		Max:   round(cp[len(cp)-1]),
	}
}

func percentile(sorted []float64, p float64) float64 {
	if len(sorted) == 0 {
		return 0
	}
	rank := int(math.Ceil((p / 100) * float64(len(sorted))))
	if rank < 1 {
		rank = 1
	}
	if rank > len(sorted) {
		rank = len(sorted)
	}
	return sorted[rank-1]
}

func nonZero(values []float64) []float64 {
	result := make([]float64, 0, len(values))
	for _, value := range values {
		if value > 0 {
			result = append(result, value)
		}
	}
	return result
}

func splitCSV(value string) []string {
	parts := strings.Split(value, ",")
	result := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			result = append(result, part)
		}
	}
	return result
}

func sanitizeTopic(topic string) string {
	replacer := strings.NewReplacer(":", "-", " ", "-", "/", "-", "\\", "-", "@", "-")
	return replacer.Replace(topic)
}

func writeJSON(path string, rep report) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	content, err := json.MarshalIndent(rep, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(content, '\n'), 0o644)
}

func writeMarkdown(path string, rep report) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	var b strings.Builder
	b.WriteString("# Отчет по нагрузочному тестированию: Sync vs Kafka\n\n")
	b.WriteString(fmt.Sprintf("Сформировано: `%s`\n\n", rep.GeneratedAt))
	b.WriteString(fmt.Sprintf("Run ID: `%s`\n\n", rep.Config.RunID))

	b.WriteString("## Методика\n\n")
	b.WriteString("Бенчмарк сравнивает две стратегии доставки одного и того же доменного события (`order.created`).\n\n")
	b.WriteString("- `sync`: producer-потоки напрямую вызывают обработчик уведомления и ждут завершения обработки.\n")
	b.WriteString("- `kafka`: producer-потоки публикуют события в Kafka, после чего benchmark consumers читают те же события и запускают тот же обработчик.\n\n")
	b.WriteString("Kafka-сценарий использует отдельный topic для каждого запуска, поэтому тест не создает реальные заказы, уведомления или письма в базах приложения.\n\n")

	b.WriteString("## Конфигурация\n\n")
	b.WriteString("| Параметр | Значение |\n|---|---:|\n")
	b.WriteString(fmt.Sprintf("| Режим | `%s` |\n", rep.Config.Mode))
	b.WriteString(fmt.Sprintf("| Количество событий | %d |\n", rep.Config.Requests))
	b.WriteString(fmt.Sprintf("| Producer concurrency | %d |\n", rep.Config.Concurrency))
	b.WriteString(fmt.Sprintf("| Kafka consumers/partitions | %d |\n", rep.Config.Consumers))
	b.WriteString(fmt.Sprintf("| Kafka brokers | `%s` |\n", strings.Join(rep.Config.Brokers, ", ")))
	b.WriteString(fmt.Sprintf("| Kafka topic | `%s` |\n", rep.Config.Topic))
	b.WriteString(fmt.Sprintf("| Моделируемая работа обработчика | `%s` |\n", rep.Config.HandlerWork))
	b.WriteString(fmt.Sprintf("| Consumer warmup | `%s` |\n", rep.Config.ConsumerWarmup))
	b.WriteString(fmt.Sprintf("| Consumer timeout | `%s` |\n\n", rep.Config.ConsumerTimeout))

	b.WriteString("## Итоги\n\n")
	b.WriteString("| Режим | Успешно | Ошибки | Длительность, с | Пропускная способность, ops/s | Основной p50, мс | Основной p95, мс | Основной p99, мс |\n")
	b.WriteString("|---|---:|---:|---:|---:|---:|---:|---:|\n")
	for _, result := range rep.Results {
		mainStats := result.OperationLatency
		if result.Mode == "kafka" {
			mainStats = result.PublishLatency
		}
		b.WriteString(fmt.Sprintf(
			"| `%s` | %d | %d | %.3f | %.2f | %s | %s | %s |\n",
			result.Mode,
			result.Success,
			result.Failed,
			result.DurationMs/1000,
			result.ThroughputOpsSec,
			statValue(mainStats, "p50"),
			statValue(mainStats, "p95"),
			statValue(mainStats, "p99"),
		))
	}

	b.WriteString("\n## Детализация задержек\n\n")
	for _, result := range rep.Results {
		b.WriteString(fmt.Sprintf("### %s\n\n", strings.ToUpper(result.Mode)))
		writeStatsTable(&b, "Задержка операции, мс", result.OperationLatency)
		writeStatsTable(&b, "Задержка публикации, мс", result.PublishLatency)
		writeStatsTable(&b, "Lag доставки, мс", result.DeliveryLag)
		writeStatsTable(&b, "Задержка обработчика, мс", result.HandlerLatency)
		if len(result.Errors) > 0 {
			b.WriteString("Ошибки:\n\n")
			for _, errText := range result.Errors {
				b.WriteString(fmt.Sprintf("- `%s`\n", errText))
			}
			b.WriteString("\n")
		}
	}

	b.WriteString("## Как использовать в дипломном отчете\n\n")
	b.WriteString("Задержку операции `sync` можно использовать как baseline, где producer ожидает завершения downstream-обработки. Задержка публикации `kafka` показывает latency, видимую producer в асинхронной архитектуре. `Delivery lag` показывает цену eventual consistency: сколько времени проходит до завершения обработки события consumer-ами.\n")

	content := append([]byte{0xEF, 0xBB, 0xBF}, []byte(b.String())...)
	return os.WriteFile(path, content, 0o644)
}

func writeStatsTable(b *strings.Builder, name string, s *stats) {
	if s == nil {
		return
	}
	b.WriteString(fmt.Sprintf("%s:\n\n", name))
	b.WriteString("| Count | Min | Mean | p50 | p90 | p95 | p99 | Max |\n")
	b.WriteString("|---:|---:|---:|---:|---:|---:|---:|---:|\n")
	b.WriteString(fmt.Sprintf("| %d | %.3f | %.3f | %.3f | %.3f | %.3f | %.3f | %.3f |\n\n", s.Count, s.Min, s.Mean, s.P50, s.P90, s.P95, s.P99, s.Max))
}

func statValue(s *stats, field string) string {
	if s == nil {
		return "-"
	}
	switch field {
	case "p50":
		return fmt.Sprintf("%.3f", s.P50)
	case "p95":
		return fmt.Sprintf("%.3f", s.P95)
	case "p99":
		return fmt.Sprintf("%.3f", s.P99)
	default:
		return "-"
	}
}

func printSummary(rep report, jsonPath, reportPath string) {
	fmt.Println("Load test completed")
	fmt.Printf("Run ID: %s\n", rep.Config.RunID)
	fmt.Printf("Topic: %s\n", rep.Config.Topic)
	for _, result := range rep.Results {
		fmt.Printf("%s: success=%d failed=%d throughput=%.2f ops/s duration=%.3fs\n",
			result.Mode,
			result.Success,
			result.Failed,
			result.ThroughputOpsSec,
			result.DurationMs/1000,
		)
	}
	fmt.Printf("JSON: %s\n", jsonPath)
	fmt.Printf("Report: %s\n", reportPath)
}

type errorCollector struct {
	limit int
	mu    sync.Mutex
	errs  []string
}

func newErrorCollector(limit int) *errorCollector {
	return &errorCollector{limit: limit}
}

func (c *errorCollector) add(err error) {
	if err == nil {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if len(c.errs) < c.limit {
		c.errs = append(c.errs, err.Error())
	}
}

func (c *errorCollector) values() []string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return append([]string(nil), c.errs...)
}

func millis(duration time.Duration) float64 {
	return float64(duration.Microseconds()) / 1000
}

func round(value float64) float64 {
	return math.Round(value*1000) / 1000
}

func randomHex(bytes int) string {
	buf := make([]byte, bytes)
	if _, err := rand.Read(buf); err != nil {
		return strconv.FormatInt(time.Now().UnixNano(), 36)
	}
	return hex.EncodeToString(buf)
}

func uuidV4() string {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return "00000000-0000-4000-8000-" + randomHex(6)
	}
	buf[6] = (buf[6] & 0x0f) | 0x40
	buf[8] = (buf[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", buf[0:4], buf[4:6], buf[6:8], buf[8:10], buf[10:])
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, "error:", err)
	os.Exit(1)
}
