# Interview Prep — H: Observability

> **Purpose**: Self-learning and revision document. These are not scripted interview answers — they are explanations to help you understand concepts and remember how they work in practice.

---

## Q1. What is observability and how is it different from monitoring?

### 1. What is this question actually asking?
- The interviewer is testing whether you understand the conceptual difference between monitoring and observability
- They want to know if you can explain why "just monitoring" isn't enough for modern systems

### 2. Understand the concept
Monitoring is about knowing when something is wrong — you define what to watch and get alerted when a threshold is breached. Observability is about understanding why something is wrong — even for situations you didn't anticipate. A well-observed system lets you ask new questions without adding new instrumentation.

### 3. The actual answer
**Monitoring**: "Is the system up? Is latency above 500ms? Alert me if CPU > 80%."
- You define metrics/checks upfront
- Answers known questions
- Good for detecting known failure modes

**Observability**: "Why is this user's request slow? What changed before the error rate spiked? Which service in the chain is causing the bottleneck?"
- You can answer unknown questions using existing telemetry
- Requires rich data: metrics + logs + traces
- Enables debugging novel failures without deploying new instrumentation

The three pillars of observability:
1. **Metrics** — aggregated numbers over time (request count, latency percentiles, error rates)
2. **Logs** — discrete timestamped events (specific request details, error messages)
3. **Traces** — end-to-end journey of a single request through all services

Your stack covers all three: Prometheus (metrics), Loki (logs), Tempo (traces).

### 4. Key takeaway
- Monitoring = alerting on known failure modes
- Observability = ability to ask arbitrary questions about system state
- Three pillars: Metrics (aggregates), Logs (events), Traces (request journey)
- Observability requires all three correlated together — Grafana provides the unified view

---

## Q2. What is Prometheus and how does it collect metrics?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand Prometheus's pull model and data model
- They are testing whether you know how Prometheus finds and scrapes targets

### 2. Understand the concept
Prometheus is a time-series database for metrics. Unlike systems where applications push metrics to a central server, Prometheus uses a pull model — it reaches out to applications and asks them for their metrics on a schedule. Applications expose metrics on an HTTP endpoint and Prometheus scrapes that endpoint periodically.

### 3. The actual answer
How Prometheus collects metrics:

```text
1. Application (Spring Boot + Micrometer) exposes:
   GET /actuator/prometheus
   → Returns metrics in Prometheus text format:
     http_server_requests_seconds_count{uri="/api/hello",status="200"} 42
     jvm_memory_used_bytes{area="heap"} 134217728
     ...

2. ServiceMonitor CRD tells Prometheus where to scrape:
   selector: app=springboot
   endpoints:
     - port: http
       path: /actuator/prometheus
       interval: 30s

3. Every 30 seconds, Prometheus:
   GET http://<pod-ip>:8080/actuator/prometheus
   → Parses response
   → Stores as time-series with timestamp + labels

4. Data stored in local TSDB (time-series database)
   Retention: 15 days (your config)
   Storage: 20Gi gp3 EBS volume
```

Prometheus data model:
- Every metric has a **name** and **labels**
- `http_server_requests_seconds_count{uri="/api/hello",status="200",method="GET"} 42`
- Labels are queryable — filter by any combination

### 4. Practical commands / examples

Command:
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```
Purpose: Access Prometheus UI locally.
What to look for: Status → Targets → see all scrape targets and their status.

Query in Prometheus UI:
```promql
# Total HTTP requests to Spring Boot
http_server_requests_seconds_count{job="springboot"}

# Request rate per second (last 5 min)
rate(http_server_requests_seconds_count{job="springboot"}[5m])
```

### 5. Key takeaway
- Prometheus = pull model (scrapes targets, not push)
- Applications expose metrics on HTTP endpoint (Micrometer does this for Spring Boot)
- ServiceMonitor CRD = tells Prometheus what to scrape (selector + path + interval)
- Data model: metric name + labels = unique time series

---

## Q3. What is a ServiceMonitor and why does it exist?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand how Prometheus discovers scrape targets in Kubernetes
- They are testing whether you know the Prometheus Operator pattern

### 2. Understand the concept
Without the Prometheus Operator, you'd configure scrape targets in Prometheus's `prometheus.yml` config file — listing every service IP and port. In Kubernetes, pod IPs change constantly. The Prometheus Operator introduces a Kubernetes-native way to configure scraping: ServiceMonitor CRDs that Prometheus Operator reads and translates into Prometheus config automatically.

### 3. The actual answer
A ServiceMonitor is a Custom Resource Definition (CRD) introduced by Prometheus Operator. It tells the Operator: "Scrape services matching these labels at this path and interval."

In your `helm/kube-prometheus-stack/values.yaml`:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: springboot
  labels:
    release: kube-prometheus-stack    # must match Prometheus's serviceMonitorSelector
spec:
  selector:
    matchLabels:
      app: springboot                 # finds Spring Boot's Service
  endpoints:
    - port: http
      path: /actuator/prometheus
      interval: 30s
  namespaceSelector:
    matchNames:
      - default
```

Flow:
```text
ServiceMonitor created
      │
      ▼
Prometheus Operator reads ServiceMonitor
      │
      ▼
Finds matching Services (app=springboot)
      │
      ▼
Translates to Prometheus scrape config
      │
      ▼
Prometheus scrapes /actuator/prometheus every 30s
```

### 4. Key takeaway
- ServiceMonitor = Kubernetes-native way to configure Prometheus scrape targets
- Prometheus Operator watches ServiceMonitors and auto-configures Prometheus
- No manual Prometheus config file editing — pure declarative CRDs
- Label `release: kube-prometheus-stack` must match Prometheus's `serviceMonitorSelector`

---

## Q4. What is PromQL and how do you write a basic query?

### 1. What is this question actually asking?
- The interviewer wants to know if you've actually used Prometheus to query data
- They are testing practical knowledge of the query language

### 2. Understand the concept
PromQL is Prometheus's query language. You use it to retrieve and calculate metrics. You need PromQL to create Grafana dashboards, write alerting rules, and investigate issues in the Prometheus UI.

### 3. The actual answer
PromQL basics:

**Instant vector** (current value):
```promql
# Current JVM heap usage
jvm_memory_used_bytes{area="heap",application="springboot"}
```

**Range vector** (values over a time range):
```promql
# Last 5 minutes of heap values
jvm_memory_used_bytes{area="heap"}[5m]
```

**Rate** (per-second rate of increase for counters):
```promql
# HTTP request rate over last 5 minutes
rate(http_server_requests_seconds_count{job="springboot"}[5m])
```

**Aggregation**:
```promql
# Total requests across all pods
sum(rate(http_server_requests_seconds_count{job="springboot"}[5m]))

# Error rate (5xx)
rate(http_server_requests_seconds_count{status=~"5.."}[5m])
```

**Percentile latency** (from histograms):
```promql
# 95th percentile latency for /api/hello
histogram_quantile(0.95,
  rate(http_server_requests_seconds_bucket{uri="/api/hello"}[5m])
)
```

Common metric types:
| Type | Description | Example |
|------|-------------|---------|
| Counter | Only goes up | Request count, error count |
| Gauge | Goes up and down | Memory usage, active connections |
| Histogram | Distribution of values | Request latency (buckets) |
| Summary | Calculated quantiles | Pre-calculated percentiles |

### 4. Key takeaway
- `rate()` = per-second rate of a counter — always use with counters, not gauges
- `sum()` = aggregate across multiple series (pods, nodes)
- `histogram_quantile()` = calculate percentile latency from histogram
- Label filters: `{status="200"}` exact, `{status=~"2.."}` regex, `{status!="200"}` not equal

---

## Q5. What is Grafana and how does it connect to Prometheus?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand the Grafana + Prometheus integration
- They are testing whether you can explain datasources and dashboards

### 2. Understand the concept
Prometheus stores metrics and provides a query interface. Grafana provides the visualization layer — it connects to Prometheus (and other sources) as a datasource and renders queries as charts, graphs, and tables. Grafana itself doesn't store data — it queries Prometheus on demand.

### 3. The actual answer
Connection flow:
```text
Grafana
  │
  │ Datasource: Prometheus
  │ URL: http://kube-prometheus-stack-prometheus.monitoring.svc:9090
  │
  ▼ PromQL query
Prometheus
  │
  ▼ Returns time-series data
Grafana
  │
  ▼ Renders as chart in dashboard panel
```

In your `helm/kube-prometheus-stack/values.yaml`, Grafana is pre-configured with datasources:
```yaml
grafana:
  additionalDataSources:
    - name: Loki
      type: loki
      url: http://loki.logging.svc.cluster.local:3100
    - name: Tempo
      type: tempo
      url: http://tempo.tracing.svc.cluster.local:3200
```

This means all three backends (Prometheus, Loki, Tempo) are available in Grafana from day one — no manual datasource setup needed.

Grafana Explore:
- Metrics tab: write PromQL queries
- Logs tab: write LogQL queries (Loki)
- Traces tab: search by trace ID or service (Tempo)

### 4. Key takeaway
- Grafana = visualization layer, doesn't store data
- Prometheus = datasource for metrics
- Loki + Tempo = additional datasources in your setup
- Datasources configured in values.yaml — no manual setup in Grafana UI needed

---

## Q6. What is an Alertmanager and how does alerting work in your stack?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand the full alerting pipeline
- They are checking if you know the difference between Prometheus rules and Alertmanager routing

### 2. Understand the concept
Prometheus evaluates alerting rules and fires alerts. But Prometheus doesn't send notifications — that's Alertmanager's job. Alertmanager receives alerts, deduplicates them, groups related alerts, applies silences, and routes them to the right notification channel.

### 3. The actual answer
Two-step alerting pipeline:

**Step 1 — Prometheus evaluates PrometheusRule:**
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: springboot-alerts
spec:
  groups:
    - name: springboot
      rules:
        - alert: HighErrorRate
          expr: rate(http_server_requests_seconds_count{status=~"5.."}[5m]) > 0.1
          for: 5m           # must be true for 5 minutes before firing
          labels:
            severity: warning
          annotations:
            summary: "High error rate on Spring Boot"
```

**Step 2 — Alertmanager routes and sends notification:**
```yaml
# Alertmanager config (simplified)
route:
  receiver: "slack-notifications"
  group_by: [alertname, severity]

receivers:
  - name: "slack-notifications"
    slack_configs:
      - channel: "#alerts"
        webhook_url: "https://hooks.slack.com/xxx"
```

Flow:
```text
Prometheus evaluates alert rule every 1 min
→ alert fires if condition is true for `for` duration
→ sends to Alertmanager
→ Alertmanager deduplicates (same alert from 5 pods = 1 notification)
→ groups by alertname + severity
→ routes to Slack/PagerDuty/email
→ sends notification
```

Your repo has kube-prometheus-stack installed which includes default Kubernetes alerting rules (pod crashes, node pressure, PVC issues, etc.).

### 4. Key takeaway
- PrometheusRule CRD = alerting rule definition (when to fire)
- Alertmanager = receives alerts, deduplicates, routes to notification channels
- `for: 5m` = alert must be true for 5 minutes before notifying (avoids flapping)
- Default kube-prometheus-stack includes 100+ pre-built Kubernetes alerting rules

---

## Q7. What is Loki and how is it different from Elasticsearch/Splunk?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand Loki's design philosophy
- They are testing whether you can explain the cost/query trade-off

### 2. Understand the concept
Traditional log systems (Elasticsearch, Splunk) index every word in every log line — enabling fast full-text search. Loki takes a different approach: only index the metadata labels (pod, namespace, application), not the log content. This makes Loki much cheaper to run but slower for arbitrary full-text searches.

### 3. The actual answer
Loki's design:

| | Loki | Elasticsearch/Splunk |
|--|------|---------------------|
| Indexing | Labels only (pod, namespace, app) | Full text of every log line |
| Storage cost | Low (compressed raw logs) | High (inverted index) |
| Query speed | Fast for label-based filter, slower for content search | Fast for any search |
| Best for | Known patterns, label-based filtering | Unknown patterns, full-text search |
| Like | Prometheus but for logs | Google for logs |

Loki query language (LogQL):
```logql
# Filter by labels (fast — index lookup)
{namespace="default", app="springboot"}

# Filter by content (slower — grep through raw logs)
{namespace="default", app="springboot"} |= "ERROR"

# Parse log line and extract fields
{app="springboot"} | json | level="ERROR"

# Rate of error logs
rate({app="springboot"} |= "ERROR" [5m])
```

In your config: Loki stores 30 days, using local filesystem (20Gi). For production at scale, you'd use S3 as object storage backend.

### 4. Key takeaway
- Loki = labels indexed (cheap), content compressed (fast storage, slower search)
- Elasticsearch = full-text indexed (expensive but fast for any query)
- Use Loki when: you know what you're looking for and filter by pod/namespace
- LogQL: label selectors first (fast), then content filter (slower)

---

## Q8. What is Promtail and how does it collect logs from Kubernetes pods?

### 1. What is this question actually asking?
- The interviewer wants to know how logs get from containers into Loki
- They are testing your understanding of the log collection pipeline

### 2. Understand the concept
Containers write logs to stdout/stderr. Kubernetes captures these and writes them as files on each node. Promtail is a log shipping agent (DaemonSet — one per node) that reads these files and forwards them to Loki with appropriate labels.

### 3. The actual answer
Log collection pipeline:

```text
Spring Boot writes to stdout:
  2024-01-01 14:32:11.123 INFO  HelloController: Processing request

Kubernetes captures stdout
→ writes to node file:
  /var/log/containers/springboot-xxx_default_springboot-xxx.log

Promtail DaemonSet (running on the same node):
  - Tails /var/log/containers/*.log
  - Detects pod name, namespace, container name from filename
  - Attaches labels:
    {
      namespace: "default",
      pod: "springboot-xxx",
      container: "springboot",
      node: "ip-10-40-2-x"
    }
  - Sends log line + labels to Loki API

Loki stores:
  label set → compressed log lines (no full text indexing)
```

Promtail automatically discovers all pods on the node — no per-application config needed. Any new pod's logs are automatically collected.

### 4. Practical commands / examples

Command:
```bash
kubectl logs <pod-name> -n default
```
Purpose: View container logs via Kubernetes API (not Loki — this is real-time from the node).

In Grafana → Explore → Loki:
```logql
{namespace="default", pod=~"springboot-.*"}
```
Purpose: See all logs from Spring Boot pods across all replicas.

### 5. Key takeaway
- Promtail = DaemonSet (one per node) that tails container log files
- Automatically discovers all pods — no per-application config
- Attaches Kubernetes metadata labels (namespace, pod, container) to every log line
- Logs available in Grafana Explore within seconds of being written

---

## Q9. What is Tempo and what is a distributed trace?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand tracing at a conceptual and practical level
- They are testing whether you know when traces are valuable vs metrics

### 2. Understand the concept
Metrics tell you: "10% of requests are slow." Logs tell you: "This specific request returned an error." Traces tell you: "This specific request went through service A → service B → database, and the database call took 2.3 seconds." Traces connect the dots across services and time for a single request.

### 3. The actual answer
A distributed trace is a record of a request's journey through a system. It consists of:

- **Trace**: One complete request journey (identified by `traceId`)
- **Span**: One operation within the trace (a function call, HTTP call, DB query)
- **Context propagation**: The `traceId` is passed in HTTP headers so child services can add their spans to the same trace

Example for your Spring Boot app:
```text
Trace: abc123
  ├── Span: springboot.GET /api/hello (45ms)
  │     ├── HTTP incoming: 2ms
  │     ├── Controller method: 40ms
  │     └── HTTP response: 3ms
```

Tempo stores these traces. When you query in Grafana by `traceId`, you see the full span tree with timing.

**When traces are most valuable**: microservices where a single request touches multiple services. For a single-service app (your current setup), traces show per-endpoint latency breakdown and detect slow code paths.

### 4. Key takeaway
- Trace = full journey of one request, identified by traceId
- Span = one operation within the trace (function, HTTP call, DB query)
- Tempo = stores and serves traces — no indexing (cheap storage)
- Most valuable in microservices — reveals which service in the chain causes latency

---

## Q10. What is OpenTelemetry and why was it created?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand the standardization problem in observability
- They are testing whether you know what problem OTel solves

### 2. Understand the concept
Before OpenTelemetry, every observability vendor had their own SDK. Switching from Datadog to Jaeger meant rewriting all your instrumentation. If you used Zipkin for traces and Prometheus for metrics, you needed two separate agents. OpenTelemetry unifies all of this under one open-source standard.

### 3. The actual answer
OpenTelemetry (OTel) is a CNCF project that provides:
1. **Specification**: Standard data formats for metrics, logs, traces
2. **SDKs**: Language-specific libraries for instrumentation (Java, Python, Go, etc.)
3. **Collector**: Infrastructure component that receives, processes, and exports telemetry

Benefits:
- **Vendor-neutral**: Instrument once, export to any backend (Prometheus, Jaeger, Datadog, etc.)
- **Auto-instrumentation**: For Java, Python, etc. — instruments common frameworks without code changes
- **Unified agent**: One collector for metrics + logs + traces (not 3 separate agents)

Before OTel:
```text
App → Jaeger SDK (traces) → Jaeger
App → Prometheus client (metrics) → Prometheus
App → FluentBit (logs) → Elasticsearch
= 3 SDKs, 3 agents, 3 configs
```

After OTel:
```text
App → OTel SDK (traces + metrics + logs) → OTel Collector → Tempo
                                                           → Prometheus
                                                           → Loki
= 1 SDK, 1 agent, 1 config
```

In your Spring Boot app:
```xml
<!-- One SDK handles all three signals -->
<dependency>
    <groupId>io.opentelemetry.instrumentation</groupId>
    <artifactId>opentelemetry-spring-boot-starter</artifactId>
</dependency>
```

### 4. Key takeaway
- OTel = unified, vendor-neutral standard for metrics + logs + traces
- Solves vendor lock-in: instrument with OTel, send to any backend
- Auto-instrumentation for Java: instruments HTTP, JDBC, etc. without code changes
- One SDK, one Collector — replaces multiple vendor-specific agents

---

## Q11. What is the OpenTelemetry Collector and why is it a separate component?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand the Collector's role as a telemetry pipeline
- They are checking why you don't just send directly from app to Prometheus/Tempo/Loki

### 2. Understand the concept
Your application could send metrics directly to Prometheus, traces directly to Tempo, and logs directly to Loki. But this creates coupling — the app needs to know about each backend's format and endpoint. The Collector acts as a middle layer: apps send everything to one place (OTLP) and the Collector handles routing to each backend.

### 3. The actual answer
The OTel Collector is a configurable telemetry pipeline:

```text
                    RECEIVERS
        ┌──────────────┬───────────────┐
        │              │               │
   OTLP gRPC    OTLP HTTP       Prometheus
  (from app)  (from app)     (scrape targets)
        │              │               │
        └──────────────┴───────────────┘
                        │
                   PROCESSORS
                        │
             ┌──────────┼──────────┐
             │          │          │
          batch    memory      k8s attr
                   limiter    (enriches with
                               pod/ns labels)
             └──────────┼──────────┘
                        │
                   EXPORTERS
        ┌──────────────┬───────────────┐
        │              │               │
   Prometheus       Tempo           Loki
   (metrics)      (traces)         (logs)
```

Benefits of the Collector:
- **Decoupling**: App doesn't need to know about backends
- **Enrichment**: k8sattributes processor adds pod, namespace, node labels automatically
- **Batching**: Reduces network calls to backends
- **Format translation**: Receive OTLP, export as Prometheus format (for Prometheus scraping)
- **Filtering/sampling**: Drop unwanted data, sample high-volume traces

Your configuration has two Collector deployments:
- **DaemonSet**: One per node — collects node metrics, kubelet metrics, K8s events
- **Deployment**: 2 replicas — receives OTLP from applications, routes to backends

### 4. Key takeaway
- Collector = telemetry pipeline (receive → process → export)
- Decouples apps from backends — app sends OTLP, Collector handles routing
- k8sattributes processor enriches all data with Kubernetes metadata
- DaemonSet (node telemetry) + Deployment (app telemetry) = complete coverage

---

## Q12. How does Micrometer connect Spring Boot to Prometheus?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand the Spring Boot metrics instrumentation layer
- They are testing whether you know what Micrometer does vs what Prometheus does

### 2. Understand the concept
Spring Boot has many internal metrics to expose — HTTP request counts, JVM memory, garbage collection, thread pools. Micrometer is the vendor-neutral metrics library that collects these and exposes them in a format specific backends can consume. Micrometer with the Prometheus registry formats them as Prometheus text exposition format.

### 3. The actual answer
Micrometer sits between Spring Boot internals and the metrics backend:

```text
Spring Boot internals:
  Tomcat connection pool
  JVM garbage collector
  HTTP request handling
  Custom business counters
        │
        ▼
  Micrometer (vendor-neutral metrics API)
  auto-instruments all of the above
        │
        ▼
  micrometer-registry-prometheus
  formats as Prometheus text:
  # HELP jvm_memory_used_bytes ...
  # TYPE jvm_memory_used_bytes gauge
  jvm_memory_used_bytes{area="heap",...} 134217728
        │
        ▼
  Exposed at: /actuator/prometheus
        │
        ▼
  Prometheus scrapes every 30s
```

Metrics exposed by Micrometer automatically for Spring Boot:
| Category | Examples |
|----------|---------|
| JVM | `jvm_memory_used_bytes`, `jvm_gc_pause_seconds` |
| HTTP server | `http_server_requests_seconds_count`, `http_server_requests_seconds_max` |
| Process | `process_cpu_usage`, `process_uptime_seconds` |
| Tomcat | `tomcat_connections_active_current` |
| Logback | `logback_events_total` (count of log events per level) |

In your `application.yml`:
```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus  # expose /actuator/prometheus
  endpoint:
    prometheus:
      enabled: true
```

### 4. Key takeaway
- Micrometer = vendor-neutral metrics instrumentation for Java
- Auto-instruments Spring Boot: JVM, HTTP, Tomcat, Logback — no code needed
- `micrometer-registry-prometheus` = formats metrics as Prometheus text
- Metrics exposed at `/actuator/prometheus` — Prometheus ServiceMonitor scrapes this

---

## Q13. What is the difference between a Prometheus Counter, Gauge, and Histogram?

### 1. What is this question actually asking?
- The interviewer is testing your understanding of Prometheus metric types
- They want to know if you know which type to use for which situation

### 2. Understand the concept
Different metrics behave differently over time. Request count only goes up (counter). Memory usage goes up and down (gauge). Request latency needs distribution information — you want to know not just average latency but also P95, P99 (histogram).

### 3. The actual answer

**Counter**: Monotonically increasing value. Never decreases (except reset to 0 on restart).
- Examples: total request count, error count, bytes received
- Query: always use `rate()` to get per-second rate
- Don't query raw counter value — it means nothing by itself

```promql
# Wrong: raw counter
http_server_requests_seconds_count

# Right: rate of change
rate(http_server_requests_seconds_count[5m])
```

**Gauge**: Value that can go up or down.
- Examples: current memory usage, active connections, number of pods
- Query: query directly (no `rate()` needed)

```promql
# Current heap usage
jvm_memory_used_bytes{area="heap"}
```

**Histogram**: Samples and counts observations in buckets.
- Used for: request latency, response size
- Provides: count, sum, and configurable buckets
- Enables percentile calculations

```promql
# P95 latency
histogram_quantile(0.95, rate(http_server_requests_seconds_bucket[5m]))
```

**Summary**: Pre-calculated quantiles (calculated in the application).
- Less flexible than histograms (can't aggregate across instances)
- Rare in modern instrumentation

### 4. Key takeaway
- Counter: only goes up → use `rate()` for per-second rate
- Gauge: goes up and down → query directly
- Histogram: distribution → use `histogram_quantile()` for percentiles
- Never use `rate()` on a gauge — it makes no sense
- Always use histograms for latency (not summaries) — allows aggregation across pods

---

## Q14. How do you correlate logs, metrics, and traces in Grafana?

### 1. What is this question actually asking?
- This is the "so what" question for the entire observability stack
- The interviewer wants to see if you can explain the practical value of having all three

### 2. Understand the concept
The real power of having Prometheus + Loki + Tempo in Grafana is correlation — jumping from a metric anomaly to the related logs to the specific trace that caused it. This is only possible when all three use the same labels (pod name, namespace) and when traces inject trace IDs into logs.

### 3. The actual answer
**Scenario**: Error rate spiked at 14:32.

**Step 1 — Start with metrics (Prometheus)**:
```promql
rate(http_server_requests_seconds_count{status=~"5..",app="springboot"}[5m])
```
→ Confirms 15% error rate spike at 14:32
→ Note the pod name from the labels: `pod="springboot-abc123"`

**Step 2 — Jump to logs (Loki)**:
```logql
{namespace="default", pod="springboot-abc123"} |= "ERROR" | time > "14:32" | time < "14:33"
```
→ Found: `NullPointerException in HelloController.java:25`
→ Log line contains: `traceId=xyz789`

**Step 3 — Jump to trace (Tempo)**:
Search by `traceId=xyz789`
→ Full request timeline:
  - Incoming HTTP: 2ms
  - Controller method: 2298ms ← bottleneck
  - Outbound HTTP to downstream: 2295ms ← external service timed out

**Result**: Root cause found — downstream service timeout causing errors in Spring Boot.

Grafana enables this workflow with:
- **Derived fields** in Loki: auto-link `traceId` in logs to Tempo search
- **Exemplars** in Prometheus: link from a high-latency metric point to the trace that caused it

### 4. Key takeaway
- Correlation workflow: Metrics → identify anomaly → Logs → find error details + traceId → Traces → find root cause
- Works because all three use same labels (pod, namespace, app)
- Grafana derived fields: auto-link traceId in logs to Tempo
- This is why all three pillars are needed — each answers a different question

---

## Q15. What is the difference between `rate()` and `irate()` in PromQL?

### 1. What is this question actually asking?
- The interviewer is testing deeper PromQL knowledge
- They want to know if you understand the trade-off between smoothness and responsiveness

### 2. Understand the concept
Both calculate per-second rate of a counter. The difference is how many data points they use to calculate it. `rate()` uses all samples in the window and calculates a linear regression — smooth but slow to react. `irate()` uses only the last two samples — responsive but spiky.

### 3. The actual answer

```promql
# Smooth rate (average over 5 minutes)
rate(http_server_requests_seconds_count[5m])

# Instant rate (last 2 samples only — more reactive)
irate(http_server_requests_seconds_count[5m])
```

| | `rate()` | `irate()` |
|--|---------|----------|
| Samples used | All in window | Last 2 samples |
| Behavior | Smooth, averaged | Spiky, instant |
| Best for | Dashboards, alert rules | Investigating sudden spikes |
| Handles gaps? | Yes | Can be inaccurate with gaps |

For alerting rules: always use `rate()` — you don't want alerts firing on momentary spikes.
For investigating a sudden spike: `irate()` shows the exact moment more clearly.

### 4. Key takeaway
- `rate()` = smooth average over the window — use for dashboards and alerts
- `irate()` = based on last 2 points — use for investigating sudden changes
- Both need a counter metric (only goes up)
- Window `[5m]` = data must exist within last 5 minutes (handles counter resets)

---

## Q16. What is kube-state-metrics and what metrics does it expose?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand how cluster-level Kubernetes metrics are exposed
- They are checking if you know the difference between node-level and cluster-level metrics

### 2. Understand the concept
node-exporter tells you about node hardware (CPU, memory, disk). But it can't tell you about Kubernetes objects — how many pods are running, is a deployment at its desired replica count, is a PVC bound? kube-state-metrics reads the Kubernetes API and exposes object state as Prometheus metrics.

### 3. The actual answer
kube-state-metrics listens to the Kubernetes API and exposes metrics about:

| Metric | Example PromQL |
|--------|---------------|
| Pod status | `kube_pod_status_phase{phase="Running"}` |
| Deployment replicas | `kube_deployment_status_replicas_available` vs `kube_deployment_spec_replicas` |
| Node status | `kube_node_status_condition{condition="Ready",status="true"}` |
| PVC status | `kube_persistentvolumeclaim_status_phase{phase="Bound"}` |
| Resource requests | `kube_pod_container_resource_requests{resource="cpu"}` |
| Container restarts | `kube_pod_container_status_restarts_total` |

Useful alert: deployment not at desired replica count for 5 minutes:
```promql
kube_deployment_status_replicas_available{deployment="springboot-springboot"}
  < kube_deployment_spec_replicas{deployment="springboot-springboot"}
```

### 4. Key takeaway
- kube-state-metrics = Kubernetes API state as Prometheus metrics
- Covers: pods, deployments, nodes, PVCs, services, namespaces, jobs
- Different from node-exporter (hardware) — this is about K8s object state
- Essential for Kubernetes health dashboards and alerting on deployment failures

---

## Q17. What are Prometheus recording rules and when would you use them?

### 1. What is this question actually asking?
- The interviewer is testing your knowledge of Prometheus performance optimization
- They want to know how to handle expensive queries at scale

### 2. Understand the concept
Some PromQL queries are computationally expensive — especially aggregations over many time series or long time ranges. Running these live on every dashboard refresh is slow and puts load on Prometheus. Recording rules pre-compute these queries and store results as new, lightweight metrics.

### 3. The actual answer
A recording rule computes a PromQL expression periodically and saves the result as a new metric:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: springboot-recording-rules
spec:
  groups:
    - name: springboot.rules
      interval: 1m         # compute every 1 minute
      rules:
        - record: job:http_requests:rate5m    # new metric name
          expr: |
            sum(rate(http_server_requests_seconds_count{job="springboot"}[5m]))
            by (status, uri)
```

Now instead of running the expensive aggregation on every dashboard refresh:
```promql
# Expensive (runs full aggregation live)
sum(rate(http_server_requests_seconds_count{job="springboot"}[5m])) by (status, uri)

# Fast (reads pre-computed result)
job:http_requests:rate5m
```

Use when:
- Dashboard query takes more than a few seconds
- Alerting rule expression is complex
- Same aggregation used by multiple dashboards

For your single-node Spring Boot setup, recording rules aren't needed yet — they matter at scale with many pods and long retention.

### 4. Key takeaway
- Recording rules = pre-compute expensive queries, store as new metric
- Naming convention: `level:metric:operation` (e.g., `job:http_requests:rate5m`)
- Speeds up dashboards and reduces Prometheus query load
- Use for expensive aggregations run frequently (dashboards, alert rules)

---

## Q18. What is log rotation and how does Kubernetes handle container logs?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand log storage management on nodes
- They are checking if you've thought about disk space for container logs

### 2. Understand the concept
Container logs written to stdout/stderr are captured by Kubernetes (via the container runtime) and stored as files on each node. Without rotation or limits, a single noisy container could fill the node's disk, causing all containers on that node to fail.

### 3. The actual answer
Kubernetes log management:
- Container logs stored at: `/var/log/containers/<pod>_<namespace>_<container>-<id>.log`
- By default, Kubernetes rotates log files when they reach 10MB (configurable)
- Keeps last 5 rotated files per container (default)

Pod-level log limits:
```yaml
# In kubelet config (node-level)
containerLogMaxSize: "10Mi"
containerLogMaxFiles: 5
```

This means max ~50MB disk per container for logs.

For Promtail: it tails these files and ships to Loki before they're rotated — logs are preserved in Loki beyond what's on disk.

Why this matters:
- High-volume logging pods can still fill disk before rotation
- Use structured logging (JSON) — easier to parse in Loki
- Set appropriate log levels in production (INFO not DEBUG) to reduce volume

### 4. Key takeaway
- Kubernetes automatically rotates container logs on nodes (default: 10MB, 5 files)
- Promtail ships logs to Loki before rotation — preserve logs beyond disk limits
- Disk space on nodes can still fill if logging volume is very high
- Production: use JSON structured logging + set appropriate log level (INFO, not DEBUG)

---

## Q19. What is the retention period in your stack and how do you configure it?

### 1. What is this question actually asking?
- The interviewer is checking if you've thought about storage costs and data lifecycle
- They want to know if you understand the trade-off between retention and storage cost

### 2. Understand the concept
Every day of retention costs storage. Prometheus with 15-day retention and 20Gi storage, Loki with 30-day retention, Tempo with 30-day retention — all require EBS volumes on EKS. Retention determines how far back you can investigate issues.

### 3. The actual answer
Your stack retention configuration:

| Component | Retention | Storage |
|-----------|-----------|---------|
| Prometheus | 15 days + 10GiB max | 20Gi gp3 EBS |
| Loki | 30 days | 20Gi gp3 EBS |
| Tempo | 30 days | 20Gi gp3 EBS |

Configuration in `values.yaml`:

**Prometheus** (`helm/kube-prometheus-stack/values.yaml`):
```yaml
prometheus:
  prometheusSpec:
    retention: 15d
    retentionSize: 10GiB    # also limits by size
    storageSpec:
      volumeClaimTemplate:
        spec:
          storage: 20Gi
```

**Loki** (`helm/loki/values.yaml`):
```yaml
config: |
  table_manager:
    retention_deletes_enabled: true
    retention_period: 30d
```

**Tempo** (`helm/tempo/values.yaml`):
```yaml
config: |
  compactor:
    compaction:
      block_retention: 30d
```

Trade-offs:
- Longer retention = more storage cost = higher EBS bill
- Shorter retention = less storage = might miss old incidents
- For compliance requirements: may need 90+ days

### 4. Key takeaway
- Retention = how long historical data is kept before deletion
- Prometheus: `retention` (time) + `retentionSize` (disk limit) — whichever hits first
- 15d metrics + 30d logs/traces is typical for dev environments
- Production: adjust based on compliance requirements and storage costs

---

## Q20. How would you debug a performance issue using your observability stack?

### 1. What is this question actually asking?
- This is a practical end-to-end scenario question
- The interviewer wants to see if you can apply all three observability pillars to solve a real problem

### 2. Understand the concept
Performance debugging requires a systematic approach — start broad (metrics), narrow down (logs), then pinpoint exactly (traces). The three pillars work together to guide you from "something is slow" to "this exact code path in this function at this time caused the latency."

### 3. The actual answer
**Scenario**: Users report the `/api/hello` endpoint is slow.

**Step 1 — Identify the problem (Metrics → Grafana → Prometheus)**:
```promql
# Check P95 latency for /api/hello
histogram_quantile(0.95,
  rate(http_server_requests_seconds_bucket{uri="/api/hello"}[5m])
)
```
→ P95 latency = 3.2 seconds (should be <100ms)

**Step 2 — When did it start? (Grafana time range)**:
→ Zoom out to 24h view → latency was normal until 14:00 today

**Step 3 — Find related logs (Loki)**:
```logql
{app="springboot"} | time > "14:00" |= "hello"
```
→ Found log lines showing slow database calls
→ `traceId=abc123xyz` present in log lines

**Step 4 — Trace the request (Tempo)**:
→ Search traceId: `abc123xyz`
→ Span tree shows:
  - Spring Boot receives request: 1ms
  - Controller method: 3200ms total
  - Outbound call to external API: 3198ms ← bottleneck

**Step 5 — Cross-reference with cluster metrics**:
```promql
# Check if external API pod was restarted
kube_pod_container_status_restarts_total{pod=~"external-api-.*"}
```
→ External API pod restarted at 14:00 → cold start causing slow responses

**Root cause**: External API dependency had a cold start after pod restart, causing slow responses for ~10 minutes.

### 4. Key takeaway
- Debug flow: Metrics (when/scope) → Logs (what error) → Traces (where exactly)
- Always correlate by time range — narrow from hours to minutes to seconds
- traceId in logs → direct link to Tempo trace = fastest path to root cause
- Cross-reference infrastructure metrics (pod restarts, node pressure) with application metrics

---

## Q21. What is the difference between a log and a metric and when would you use each?

### 1. What is this question actually asking?
- The interviewer is checking your conceptual clarity about the two most common telemetry signals
- They want to know that you don't try to use one where the other is more appropriate

### 2. Understand the concept
Metrics and logs serve different purposes and have different cost profiles. Using the right one for the right situation makes observability more efficient and less expensive.

### 3. The actual answer

| | Metric | Log |
|--|--------|-----|
| Format | Number + labels (aggregated) | Text string (discrete event) |
| Granularity | Aggregated (count, rate, average) | Individual event detail |
| Storage cost | Very low (numbers) | Higher (text, compressed) |
| Query speed | Very fast | Moderate |
| Best for | Trends, rates, percentiles, alerting | Debugging, event details, audit |
| Example | "1000 requests/second, 2% error rate" | "Request failed for user_id=123: NullPointerException at line 45" |

Decision guide:
- **Use a metric when**: you want to track rates, counts, percentiles, or trigger alerts
  - "How many requests per second?" → metric
  - "Is P95 latency > 500ms?" → metric + alert
  - "How much memory is JVM using?" → metric

- **Use a log when**: you need details about a specific event
  - "What was the exact error for this request?" → log
  - "What parameters did user 123 send?" → log
  - "What was the stack trace?" → log

Common anti-patterns:
- Logging every request with full body → use metrics for counts, log only errors
- Creating metrics from string parsing → use structured logs + LogQL

### 4. Key takeaway
- Metrics = aggregated numbers, cheap to store, fast to query, great for alerting
- Logs = discrete events, richer detail, more expensive, essential for debugging
- Rule: if you're trying to COUNT or RATE something → metric; if you need DETAILS → log
- Both needed: metrics tell you there's a problem, logs tell you why
