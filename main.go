package main

import (
	"context"
	"crypto/rand"
	"flag"
	"fmt"
	"log"
	"sync"
	"sync/atomic"
	"time"

	// NATS
	nats "github.com/nats-io/nats.go"
	// Kafka
	"github.com/segmentio/kafka-go"
	// Pulsar
	"github.com/apache/pulsar-client-go/pulsar"
)

type metrics struct {
	sent, acks uint64
	start      time.Time
	durations  []time.Duration
	mu         sync.Mutex
}

func (m *metrics) add(d time.Duration) {
	m.mu.Lock()
	m.durations = append(m.durations, d)
	m.mu.Unlock()
}

func percentiles(ds []time.Duration) (p50, p95 time.Duration) {
	if len(ds) == 0 {
		return 0, 0
	}
	// simple nth-element-ish selection by sort
	tmp := make([]time.Duration, len(ds))
	copy(tmp, ds)
	// insertion sort for brevity
	for i := 1; i < len(tmp); i++ {
		j := i
		for j > 0 && tmp[j-1] > tmp[j] {
			tmp[j-1], tmp[j] = tmp[j], tmp[j-1]
			j--
		}
	}
	idx := func(p float64) int {
		n := int(float64(len(tmp)-1) * p / 100.0)
		if n < 0 {
			n = 0
		}
		if n >= len(tmp) {
			n = len(tmp) - 1
		}
		return n
	}
	return tmp[idx(50)], tmp[idx(95)]
}

func payload(size int) []byte {
	b := make([]byte, size)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return b
}

func main() {
	system := flag.String("system", "nats", "nats|kafka|pulsar")
	servers := flag.String("servers", "", "bootstrap URLs. nats: nats://host:4222; kafka: host:9092; pulsar: pulsar://host:6650")
	topic := flag.String("topic", "bench", "subject/topic")
	messages := flag.Int("messages", 100000, "number of messages")
	size := flag.Int("size", 512, "payload bytes")
	concurrency := flag.Int("concurrency", 64, "parallel publishers")
	partitions := flag.Int("partitions", 6, "kafka partitions to use/create")
	jsReplicas := flag.Int("js-replicas", 3, "nats jetstream replicas")
	pTenant := flag.String("pulsar-tenant", "public", "pulsar tenant")
	pNs := flag.String("pulsar-namespace", "default", "pulsar namespace")
	flag.Parse()

	switch *system {
	case "nats":
		runNATS(*servers, *topic, *messages, *size, *concurrency, *jsReplicas)
	case "kafka":
		runKafka(*servers, *topic, *messages, *size, *concurrency, *partitions)
	case "pulsar":
		runPulsar(*servers, *topic, *messages, *size, *concurrency, *pTenant, *pNs)
	default:
		log.Fatalf("unknown system: %s", *system)
	}
}

func runNATS(servers, subj string, total, sz, conc, replicas int) {
	if servers == "" {
		log.Fatal("servers required")
	}
	nc, err := nats.Connect(servers, nats.Name("bench-nats"))
	if err != nil {
		log.Fatal(err)
	}
	defer nc.Drain()
	js, err := nc.JetStream(nats.PublishAsyncMaxPending(conc * 2))
	if err != nil {
		log.Fatal(err)
	}
	// Ensure stream
	stream := "S_BENCH"
	_, _ = js.AddStream(&nats.StreamConfig{
		Name:      stream,
		Subjects:  []string{subj},
		Replicas:  replicas,
		Storage:   nats.FileStorage,
		Retention: nats.LimitsPolicy,
	}, nats.Context(context.Background()))

	msg := payload(sz)
	var m metrics
	m.start = time.Now()
	wg := sync.WaitGroup{}
	per := total / conc
	rem := total % conc
	ctx := context.Background()

	for i := 0; i < conc; i++ {
		n := per
		if i < rem {
			n++
		}
		if n == 0 {
			continue
		}
		wg.Add(1)
		go func(n int) {
			defer wg.Done()
			for j := 0; j < n; j++ {
				t0 := time.Now()
				pa, err := js.Publish(subj, msg, nats.Context(ctx))
				if err != nil {
					log.Fatal(err)
				}
				_ = pa
				atomic.AddUint64(&m.sent, 1)
				atomic.AddUint64(&m.acks, 1)
				m.add(time.Since(t0))
			}
		}(n)
	}
	wg.Wait()
	elapsed := time.Since(m.start).Seconds()
	p50, p95 := percentiles(m.durations)
	fmt.Printf("NATS JetStream | msgs=%d size=%dB conc=%d replicas=%d\n", total, sz, conc, replicas)
	fmt.Printf("Throughput: %.0f msg/s, %.2f MB/s\n", float64(total)/elapsed, (float64(total*sz)/1e6)/elapsed)
	fmt.Printf("Latency: p50=%s p95=%s\n", p50, p95)
}

func runKafka(bootstrap, topic string, total, sz, conc, partitions int) {
	if bootstrap == "" {
		log.Fatal("servers required")
	}
	// Create topic if not exists (best-effort)
	// kafka-go can auto-create with broker config; otherwise pre-create outside.
	w := &kafka.Writer{
		Addr:                   kafka.TCP(bootstrap),
		Topic:                  topic,
		Balancer:               &kafka.Hash{},
		RequiredAcks:           kafka.RequireAll,
		Async:                  false,
		AllowAutoTopicCreation: true,
		BatchSize:              1,
	}
	defer w.Close()

	msg := payload(sz)
	var m metrics
	m.start = time.Now()
	wg := sync.WaitGroup{}
	per := total / conc
	rem := total % conc

	for i := range conc {
		n := per
		if i < rem {
			n++
		}
		if n == 0 {
			continue
		}
		wg.Add(1)
		go func(n int) {
			defer wg.Done()
			for range n {
				t0 := time.Now()
				err := w.WriteMessages(context.Background(), kafka.Message{Key: nil, Value: msg})
				if err != nil {
					log.Fatal(err)
				}
				atomic.AddUint64(&m.sent, 1)
				atomic.AddUint64(&m.acks, 1)
				m.add(time.Since(t0))
			}
		}(n)
	}
	wg.Wait()
	elapsed := time.Since(m.start).Seconds()
	p50, p95 := percentiles(m.durations)
	fmt.Printf("Kafka | msgs=%d size=%dB conc=%d partitions~%d\n", total, sz, conc, partitions)
	fmt.Printf("Throughput: %.0f msg/s, %.2f MB/s\n", float64(total)/elapsed, (float64(total*sz)/1e6)/elapsed)
	fmt.Printf("Latency: p50=%s p95=%s\n", p50, p95)
}

func runPulsar(serviceURL, topic string, total, sz, conc int, tenant, ns string) {
	if serviceURL == "" {
		log.Fatal("servers required")
	}
	client, err := pulsar.NewClient(pulsar.ClientOptions{
		URL:               serviceURL,
		OperationTimeout:  30 * time.Second,
		ConnectionTimeout: 30 * time.Second,
	})
	if err != nil {
		log.Fatal(err)
	}
	defer client.Close()

	fullTopic := fmt.Sprintf("persistent://%s/%s/%s", tenant, ns, topic)
	prod, err := client.CreateProducer(pulsar.ProducerOptions{
		Topic:                   fullTopic,
		DisableBlockIfQueueFull: false,
		DisableBatching:         true, // measure per-message acks
	})
	if err != nil {
		log.Fatal(err)
	}
	defer prod.Close()

	msg := payload(sz)
	var m metrics
	m.start = time.Now()
	wg := sync.WaitGroup{}
	per := total / conc
	rem := total % conc

	for i := 0; i < conc; i++ {
		n := per
		if i < rem {
			n++
		}
		if n == 0 {
			continue
		}
		wg.Add(1)
		go func(n int) {
			defer wg.Done()
			ctx := context.Background()
			for j := 0; j < n; j++ {
				t0 := time.Now()
				_, err := prod.Send(ctx, &pulsar.ProducerMessage{Payload: msg})
				if err != nil {
					log.Fatal(err)
				}
				atomic.AddUint64(&m.sent, 1)
				atomic.AddUint64(&m.acks, 1)
				m.add(time.Since(t0))
			}
		}(n)
	}
	wg.Wait()
	elapsed := time.Since(m.start).Seconds()
	p50, p95 := percentiles(m.durations)
	fmt.Printf("Pulsar | msgs=%d size=%dB conc=%d\n", total, sz, conc)
	fmt.Printf("Throughput: %.0f msg/s, %.2f MB/s\n", float64(total)/elapsed, (float64(total*sz)/1e6)/elapsed)
	fmt.Printf("Latency: p50=%s p95=%s\n", p50, p95)
}
