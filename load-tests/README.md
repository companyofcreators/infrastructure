# Нагрузочные тесты

В этой папке лежат воспроизводимые нагрузочные тесты для сравнения двух вариантов доставки событий:

- синхронная обработка без Kafka;
- асинхронная обработка через Kafka.

Первый бенчмарк называется `event-pipeline`. В обоих режимах он использует одинаковый payload, похожий на доменное событие `order.created`. В режиме `sync` обработчик уведомления вызывается напрямую. В режиме `kafka` события публикуются в изолированный topic `load.events.<run_id>`, а benchmark consumers читают эти события и запускают тот же обработчик.

Тест не создает реальные заказы, уведомления, пользователей или письма в базах приложения. Поэтому его можно безопасно запускать перед подготовкой дипломного отчета, не засоряя Mailpit и бизнес-таблицы.

## Требования

Сначала подними инфраструктуру:

```powershell
docker compose up -d
```

Kafka должна быть доступна с хоста по адресу `localhost:29092`.

## Быстрый запуск

```powershell
cd .\load-tests\event-pipeline
go run . --mode both --requests 1000 --concurrency 50 --consumers 4
```

Команда создает:

- JSON с результатами: `load-tests/results/event-pipeline-<run_id>.json`;
- Markdown-отчет: `load-tests/results/event-pipeline-<run_id>.md`.

## Прогоны для отчета

Для финальных цифр используй одну и ту же машину и закрой тяжелые фоновые процессы.

Чистый overhead транспорта:

```powershell
cd .\load-tests\event-pipeline

go run . --mode both --requests 1000  --concurrency 25  --consumers 4
go run . --mode both --requests 5000  --concurrency 50  --consumers 4
go run . --mode both --requests 10000 --concurrency 100 --consumers 8
```

Моделирование downstream-работы, ближе к реальному пайплайну уведомлений с БД и отправкой письма:

```powershell
cd .\load-tests\event-pipeline

go run . --mode both --requests 1000  --concurrency 25  --consumers 4 --handler-work 20ms
go run . --mode both --requests 5000  --concurrency 50  --consumers 4 --handler-work 20ms
go run . --mode both --requests 10000 --concurrency 100 --consumers 8 --handler-work 20ms
```

Для дипломного текста сравнивай:

- `sync` operation latency: сколько producer ждет при синхронной downstream-обработке;
- `kafka` publish latency: сколько producer ждет в асинхронной архитектуре;
- `kafka` delivery lag: задержка eventual consistency до завершения обработки consumer-ами.

Если `--handler-work` равен `0`, sync-режим обычно быстрее по latency одной операции, потому что downstream-работа почти отсутствует. Такой прогон полезен для оценки overhead Kafka. При ненулевой downstream-работе Kafka обычно снижает producer-facing latency, но переносит оставшуюся обработку в delivery lag.

## Очистка тестовых topic

Каждый запуск создает отдельный topic вида `load.events.load-20260526-120000-ab12cd34`. Старые benchmark topics можно удалить через Kafka UI на `http://localhost:8088` или командой:

```powershell
docker exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --delete --topic <topic-name>
```
