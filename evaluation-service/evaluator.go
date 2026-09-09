package main

import (
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	neturl "net/url"
	"os"
	"strings"
	"sync"
	"time"
)

const (
	// Tempo de vida do cache em segundos
	CACHE_TTL = 30 * time.Second
)

// NOTA SOBRE AS SUPRESSOES DE gosec NESTE ARQUIVO
//
// A analise de taint do gosec (G704/G706) rastreia o dado da entrada ate o
// destino, mas nao possui lista de sanitizadores reconhecidos: ela continua
// acusando mesmo depois de neturl.PathEscape e de sanitizarParaLog.
//
// Por isso as supressoes sao por LINHA, e nao por regra: um `http.NewRequest`
// ou um `log.Printf` novo, sem sanitizacao, continua sendo reprovado pelo
// pipeline. Cada supressao fica ao lado da chamada que ja foi tratada.

// sanitizarParaLog remove quebras de linha e caracteres de controle de valores
// que vieram do cliente antes de irem para o log (gosec G706).
//
// Sem isso, um flag_name contendo "\n" permite forjar linhas inteiras de log:
// quem depois lê esse log — ou o SIEM que o indexa — passa a ver eventos que
// nunca aconteceram.
func sanitizarParaLog(valor string) string {
	limpo := strings.Map(func(r rune) rune {
		if r == '\n' || r == '\r' || r < 32 || r == 127 {
			return -1
		}
		return r
	}, valor)

	const maximo = 120
	if len(limpo) > maximo {
		return limpo[:maximo] + "..."
	}
	return limpo
}

// getDecision é o wrapper principal
func (a *App) getDecision(userID, flagName string) (bool, error) {
	// 1. Obter os dados da flag (do cache ou dos serviços)
	info, err := a.getCombinedFlagInfo(flagName)
	if err != nil {
		return false, err
	}

	// 2. Executar a lógica de avaliação
	return a.runEvaluationLogic(info, userID), nil
}

// getCombinedFlagInfo busca os dados no Redis, com fallback para os microsserviços
func (a *App) getCombinedFlagInfo(flagName string) (*CombinedFlagInfo, error) {
	cacheKey := fmt.Sprintf("flag_info:%s", flagName)

	// 1. Tentar buscar do Cache (Redis)
	val, err := a.RedisClient.Get(ctx, cacheKey).Result()
	if err == nil {
		// Cache HIT
		var info CombinedFlagInfo
		if err := json.Unmarshal([]byte(val), &info); err == nil {
			log.Printf("Cache HIT para flag '%s'", sanitizarParaLog(flagName)) //nolint:gosec // #nosec G706 -- valor ja passou por sanitizarParaLog
			return &info, nil
		}
		// Se o unmarshal falhar, trata como cache miss
		log.Printf("Erro ao desserializar cache para flag '%s': %v", sanitizarParaLog(flagName), err) //nolint:gosec // #nosec G706 -- valor ja passou por sanitizarParaLog
	}

	log.Printf("Cache MISS para flag '%s'", sanitizarParaLog(flagName)) //nolint:gosec // #nosec G706 -- valor ja passou por sanitizarParaLog
	// 2. Cache MISS - Buscar dos serviços
	info, err := a.fetchFromServices(flagName)
	if err != nil {
		return nil, err
	}

	// 3. Salvar no Cache
	jsonData, err := json.Marshal(info)
	if err == nil {
		// Falha ao gravar no cache não invalida a resposta: o próximo pedido
		// simplesmente volta a consultar os serviços de origem.
		if err := a.RedisClient.Set(ctx, cacheKey, jsonData, CACHE_TTL).Err(); err != nil {
			log.Printf("Aviso: falha ao gravar a flag '%s' no cache: %v", sanitizarParaLog(flagName), err) //nolint:gosec // #nosec G706 -- valor ja passou por sanitizarParaLog
		}
	}

	return info, nil
}

// fetchFromServices busca dados do flag-service e targeting-service concorrentemente
func (a *App) fetchFromServices(flagName string) (*CombinedFlagInfo, error) {
	var wg sync.WaitGroup
	wg.Add(2)

	var flagInfo *Flag
	var ruleInfo *TargetingRule
	var flagErr, ruleErr error

	// Goroutine 1: Buscar do flag-service
	go func() {
		defer wg.Done()
		flagInfo, flagErr = a.fetchFlag(flagName)
	}()

	// Goroutine 2: Buscar do targeting-service
	go func() {
		defer wg.Done()
		ruleInfo, ruleErr = a.fetchRule(flagName)
	}()

	wg.Wait()

	if flagErr != nil {
		return nil, flagErr
	}
	if ruleErr != nil {
		log.Printf("Aviso: Nenhuma regra de segmentação encontrada para '%s'. Usando padrão.", sanitizarParaLog(flagName)) //nolint:gosec // #nosec G706 -- valor ja passou por sanitizarParaLog
	}

	return &CombinedFlagInfo{
		Flag: flagInfo,
		Rule: ruleInfo,
	}, nil
}

// fetchFlag (função helper)
func (a *App) fetchFlag(flagName string) (*Flag, error) {
	// gosec G704: flagName vem da query string. Sem escapar, um valor
	// como "../admin" sairia do caminho pretendido dentro do flag-service.
	url := fmt.Sprintf("%s/flags/%s", a.FlagServiceURL, neturl.PathEscape(flagName))

	apiKey := os.Getenv("SERVICE_API_KEY")
	req, _ := http.NewRequest("GET", url, nil) //nolint:gosec // #nosec G704 -- caminho escapado com neturl.PathEscape
	req.Header.Set("Authorization", "Bearer "+apiKey)

	resp, err := a.HttpClient.Do(req) //nolint:gosec // #nosec G704 -- caminho escapado com neturl.PathEscape
	if err != nil {
		return nil, fmt.Errorf("erro ao chamar flag-service: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode == http.StatusNotFound {
		return nil, &NotFoundError{flagName}
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("flag-service retornou status %d", resp.StatusCode)
	}

	body, _ := io.ReadAll(resp.Body)
	var flag Flag
	if err := json.Unmarshal(body, &flag); err != nil {
		return nil, fmt.Errorf("erro ao desserializar resposta do flag-service: %w", err)
	}
	return &flag, nil
}

func (a *App) fetchRule(flagName string) (*TargetingRule, error) {
	// gosec G704: mesmo tratamento do fetchFlag.
	url := fmt.Sprintf("%s/rules/%s", a.TargetingServiceURL, neturl.PathEscape(flagName))
	apiKey := os.Getenv("SERVICE_API_KEY")     // Usa a mesma chave
	req, _ := http.NewRequest("GET", url, nil) //nolint:gosec // #nosec G704 -- caminho escapado com neturl.PathEscape
	req.Header.Set("Authorization", "Bearer "+apiKey)

	resp, err := a.HttpClient.Do(req) //nolint:gosec // #nosec G704 -- caminho escapado com neturl.PathEscape
	if err != nil {
		return nil, fmt.Errorf("erro ao chamar targeting-service: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode == http.StatusNotFound {
		return nil, &NotFoundError{flagName} // Não é um erro fatal
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("targeting-service retornou status %d", resp.StatusCode)
	}

	body, _ := io.ReadAll(resp.Body)
	var rule TargetingRule
	if err := json.Unmarshal(body, &rule); err != nil {
		return nil, fmt.Errorf("erro ao desserializar resposta do targeting-service: %w", err)
	}
	return &rule, nil
}

// runEvaluationLogic é onde a decisão é tomada
func (a *App) runEvaluationLogic(info *CombinedFlagInfo, userID string) bool {
	if info.Flag == nil || !info.Flag.IsEnabled {
		return false
	}

	if info.Rule == nil || !info.Rule.IsEnabled {
		return true
	}

	// 3. Processa a regra (só temos "PERCENTAGE" por enquanto)
	rule := info.Rule.Rules
	if rule.Type == "PERCENTAGE" {
		// Converte o 'value' (que é interface{}) para float64
		percentage, ok := rule.Value.(float64)
		if !ok {
			log.Printf("Erro: valor da regra de porcentagem não é um número para a flag '%s'", sanitizarParaLog(info.Flag.Name)) //nolint:gosec // #nosec G706 -- valor ja passou por sanitizarParaLog
			return false
		}

		// Calcula o "bucket" do usuário (0-99)
		userBucket := getDeterministicBucket(userID + info.Flag.Name)

		if float64(userBucket) < percentage {
			return true
		}
	}

	return false
}

func getDeterministicBucket(input string) int {
	// SHA-256 sobre a chave "userID+flagName" e os 4 primeiros bytes.
	// A escolha por SHA-256 veio de um achado do gosec (G505: crypto/sha1);
	// o uso aqui não é criptográfico, mas manter SHA-1 no código deixaria um
	// falso positivo permanente no pipeline de segurança.
	hasher := sha256.New()
	hasher.Write([]byte(input))
	hash := hasher.Sum(nil)

	// Converte 4 bytes para um uint32
	val := binary.BigEndian.Uint32(hash[:4])

	// Retorna o módulo 100
	return int(val % 100)
}
