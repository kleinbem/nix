package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	VAULT_PATH = "/home/martin/Documents/Notes"
	INDEX_PATH = "/home/martin/Develop/github.com/kleinbem/nix/scratch/semantic_index.json"
	MODEL      = "nomic-embed-text"
)

func getOllamaUrl() string {
	endpoints := []string{
		"http://localhost:11434/api/embeddings",
		"http://10.85.46.104:11434/api/embeddings",
		"http://10.85.46.126:11434/api/embeddings",
	}

	// Try to get from inventory.nix
	invPath := "/home/martin/Develop/github.com/kleinbem/nix/nix-config/inventory.nix"
	if _, err := os.Stat(invPath); err == nil {
		cmd := exec.Command("nix", "eval", "--json", "--file", invPath)
		var out bytes.Buffer
		cmd.Stdout = &out
		if err := cmd.Run(); err == nil {
			var inv struct {
				Network struct {
					Nodes map[string]struct {
						IP string `json:"ip"`
					} `json:"nodes"`
				} `json:"network"`
			}
			if err := json.Unmarshal(out.Bytes(), &inv); err == nil {
				if orin, ok := inv.Network.Nodes["ollama-orin"]; ok && orin.IP != "" {
					ip := orin.IP
					newEndpoint := fmt.Sprintf("http://%s:11434/api/embeddings", ip)
					// insert at index 1
					endpoints = append(endpoints[:1], append([]string{newEndpoint}, endpoints[1:]...)...)
				}
			}
		}
	}

	client := http.Client{Timeout: 500 * time.Millisecond}
	for _, url := range endpoints {
		parts := strings.Split(url, "/")
		if len(parts) > 3 {
			baseUrl := strings.Join(parts[:len(parts)-2], "/")
			resp, err := client.Get(baseUrl + "/tags")
			if err == nil && resp.StatusCode == 200 {
				resp.Body.Close()
				return url
			}
			if err == nil {
				resp.Body.Close()
			}
		}
	}

	return "http://localhost:11434/api/embeddings"
}

type EmbeddingRequest struct {
	Model  string `json:"model"`
	Prompt string `json:"prompt"`
}

type EmbeddingResponse struct {
	Embedding []float64 `json:"embedding"`
}

type IndexEntry struct {
	Title     string    `json:"title"`
	Path      string    `json:"path"`
	Excerpt   string    `json:"excerpt"`
	Embedding []float64 `json:"embedding"`
}

type Job struct {
	Path     string
	Filename string
}

func worker(id int, ollamaUrl string, jobs <-chan Job, results chan<- *IndexEntry, wg *sync.WaitGroup) {
	defer wg.Done()
	client := http.Client{Timeout: 10 * time.Second}

	for job := range jobs {
		contentBytes, err := os.ReadFile(job.Path)
		if err != nil {
			fmt.Printf("Worker %d: error reading %s: %v\n", id, job.Path, err)
			continue
		}
		content := string(contentBytes)
		
		prompt := content
		if len(prompt) > 1000 {
			prompt = prompt[:1000]
		}

		excerpt := content
		if len(excerpt) > 200 {
			excerpt = excerpt[:200]
		}

		reqBody, _ := json.Marshal(EmbeddingRequest{
			Model:  MODEL,
			Prompt: prompt,
		})

		resp, err := client.Post(ollamaUrl, "application/json", bytes.NewBuffer(reqBody))
		if err != nil {
			continue
		}
		
		if resp.StatusCode != 200 {
			resp.Body.Close()
			continue
		}

		var embedResp EmbeddingResponse
		if err := json.NewDecoder(resp.Body).Decode(&embedResp); err != nil {
			resp.Body.Close()
			continue
		}
		resp.Body.Close()

		// Skip empty embeddings just in case
		if len(embedResp.Embedding) == 0 {
			continue
		}

		results <- &IndexEntry{
			Title:     job.Filename,
			Path:      job.Path,
			Excerpt:   excerpt,
			Embedding: embedResp.Embedding,
		}
		fmt.Printf("  - Processed %s\n", job.Filename)
	}
}

func main() {
	ollamaUrl := getOllamaUrl()
	fmt.Printf("🤖 Using Ollama embedding endpoint: %s\n", ollamaUrl)

	fmt.Printf("🔍 Indexing vault: %s\n", VAULT_PATH)

	if _, err := os.Stat(VAULT_PATH); os.IsNotExist(err) {
		fmt.Printf("❌ Vault path not found: %s\n", VAULT_PATH)
		return
	}

	jobs := make(chan Job, 5000)
	results := make(chan *IndexEntry, 5000)
	var wg sync.WaitGroup

	numWorkers := 10 // Process 10 files concurrently
	for w := 1; w <= numWorkers; w++ {
		wg.Add(1)
		go worker(w, ollamaUrl, jobs, results, &wg)
	}

	go func() {
		filepath.Walk(VAULT_PATH, func(path string, info os.FileInfo, err error) error {
			if err == nil && !info.IsDir() && strings.HasSuffix(info.Name(), ".md") {
				jobs <- Job{Path: path, Filename: info.Name()}
			}
			return nil
		})
		close(jobs)
	}()

	go func() {
		wg.Wait()
		close(results)
	}()

	var index []*IndexEntry
	for entry := range results {
		index = append(index, entry)
	}

	os.MkdirAll(filepath.Dir(INDEX_PATH), 0755)
	
	f, err := os.Create(INDEX_PATH)
	if err != nil {
		fmt.Printf("Error creating index file: %v\n", err)
		return
	}
	defer f.Close()

	if err := json.NewEncoder(f).Encode(index); err != nil {
		fmt.Printf("Error encoding JSON: %v\n", err)
	}

	fmt.Printf("✅ Index saved to %s (%d documents)\n", INDEX_PATH, len(index))
}
