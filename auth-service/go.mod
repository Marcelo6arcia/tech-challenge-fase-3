module auth-service

go 1.23

require (
	github.com/jackc/pgx/v4 v4.18.3
	github.com/joho/godotenv v1.5.1
)

// Bumps explícitos exigidos pelo SCA da Fase 3.
//
// golang.org/x/crypto: o Trivy reprovou o build com 5 advisories CRITICAL
// (GHSA-x527-x647-q7gg, GHSA-5cgq-3rg8-m6cv, GHSA-rm3j-f69w-wqmq,
// GHSA-89gr-r52h-f8rx, GHSA-vgwf-h737-ff37), todas corrigidas na 0.52.0.
// Nenhuma delas nos afeta na prática — são falhas do servidor SSH, e este
// serviço só usa o pacote via pgx — mas a política é não deixar CRITICAL passar.
require (
	golang.org/x/crypto v0.52.0
	golang.org/x/text v0.21.0
)

require (
	github.com/jackc/chunkreader/v2 v2.0.1 // indirect
	github.com/jackc/pgconn v1.14.3 // indirect
	github.com/jackc/pgio v1.0.0 // indirect
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgproto3/v2 v2.3.3 // indirect
	github.com/jackc/pgservicefile v0.0.0-20221227161230-091c0ba34f0a // indirect
	github.com/jackc/pgtype v1.14.0 // indirect
	github.com/pkg/errors v0.9.1 // indirect
)
