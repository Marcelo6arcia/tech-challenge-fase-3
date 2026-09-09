module evaluation-service

go 1.23

require (
	github.com/aws/aws-sdk-go v1.55.5
	github.com/go-redis/redis/v8 v8.11.5
	github.com/joho/godotenv v1.5.1
)

// Bump explícito exigido pelo SCA da Fase 3:
//   golang.org/x/net < 0.33.0 -> CVE-2024-45338 (DoS no parser HTML)
require golang.org/x/net v0.33.0

require (
	github.com/cespare/xxhash/v2 v2.2.0 // indirect
	github.com/dgryski/go-rendezvous v0.0.0-20200823014737-9f7001d12a5f // indirect
	github.com/jmespath/go-jmespath v0.4.0 // indirect
)
