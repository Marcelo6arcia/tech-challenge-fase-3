module evaluation-service

go 1.25.0

require (
	github.com/aws/aws-sdk-go v1.55.5
	github.com/go-redis/redis/v8 v8.11.5
	github.com/joho/godotenv v1.5.1
)

// Bump explícito exigido pelo SCA da Fase 3:
//   < 0.33.0 -> CVE-2024-45338 (DoS no parser HTML)
//   < 0.55.0 -> GHSA-5cv4-jp36-h3mw, GHSA-vvgc-356p-c3xw, GHSA-qxp5-gwg8-xv66
require golang.org/x/net v0.55.0 // indirect

require (
	github.com/cespare/xxhash/v2 v2.2.0 // indirect
	github.com/dgryski/go-rendezvous v0.0.0-20200823014737-9f7001d12a5f // indirect
	github.com/jmespath/go-jmespath v0.4.0 // indirect
	golang.org/x/sys v0.45.0 // indirect
)
