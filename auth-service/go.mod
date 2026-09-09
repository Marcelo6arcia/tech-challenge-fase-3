module auth-service

go 1.25.0

require (
	github.com/jackc/pgx/v4 v4.18.3
	github.com/joho/godotenv v1.5.1
)

// Bumps explícitos exigidos pelo SCA da Fase 3.
//
// golang.org/x/crypto: o SCA reprovou o build duas vezes seguidas.
// Primeiro por 5 advisories CRITICAL corrigidas na 0.52.0; depois pela
// CVE-2026-56854 (bypass de autenticação por restrição de origem não aplicada
// no servidor SSH), corrigida na 0.55.0.
// Nenhuma delas nos afeta na prática — este serviço só usa o pacote via pgx,
// e nunca sobe um servidor SSH — mas a política é não deixar CRITICAL passar.
require (
	golang.org/x/crypto v0.55.0
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
