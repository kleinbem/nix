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
	"sync/atomic"
	"time"
)

const MODEL = "nomic-embed-text"

// Set in main: the vault atlas_mcp searches, and nix/scratch/ where its
// semantic_search reads the index. workspace-indexer.sh sets INDEXER_NIX_ROOT.
var (
	VAULT_PATH string
	INDEX_PATH string
	NIX_ROOT   string
)

func getOllamaUrl() string {
	endpoints := []string{
		"http://localhost:11434/api/embeddings",
		"http://10.85.46.104:11434/api/embeddings",
		"http://10.85.46.126:11434/api/embeddings",
	}

	// Try to get from inventory.nix
	invPath := filepath.Join(filepath.Dir(NIX_ROOT), "nix-config", "inventory.nix")
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
			resp, err := client.Get(baseUrl + "/api/tags")
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

func worker(id int, ollamaUrl string, jobs <-chan Job, results chan<- *IndexEntry, failed *atomic.Int64, wg *sync.WaitGroup) {
	defer wg.Done()
	client := http.Client{Timeout: 10 * time.Second}

	for job := range jobs {
		contentBytes, err := os.ReadFile(job.Path)
		if err != nil {
			fmt.Printf("Worker %d: error reading %s: %v\n", id, job.Path, err)
			failed.Add(1)
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
			fmt.Printf("Worker %d: skipped %s: %v\n", id, job.Filename, err)
			failed.Add(1)
			continue
		}

		if resp.StatusCode != 200 {
			resp.Body.Close()
			fmt.Printf("Worker %d: skipped %s: HTTP %d\n", id, job.Filename, resp.StatusCode)
			failed.Add(1)
			continue
		}

		var embedResp EmbeddingResponse
		if err := json.NewDecoder(resp.Body).Decode(&embedResp); err != nil {
			resp.Body.Close()
			fmt.Printf("Worker %d: skipped %s: %v\n", id, job.Filename, err)
			failed.Add(1)
			continue
		}
		resp.Body.Close()

		if len(embedResp.Embedding) == 0 {
			fmt.Printf("Worker %d: skipped %s: empty embedding\n", id, job.Filename)
			failed.Add(1)
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
	home, err := os.UserHomeDir()
	if err != nil {
		fmt.Printf("❌ No home directory: %v\n", err)
		os.Exit(1)
	}
	VAULT_PATH = filepath.Join(home, "Documents", "Notes")
	NIX_ROOT = os.Getenv("INDEXER_NIX_ROOT")
	if NIX_ROOT == "" {
		NIX_ROOT = filepath.Join(home, "Develop", "github.com", "kleinbem", "nix")
	}
	INDEX_PATH = filepath.Join(NIX_ROOT, "scratch", "semantic_index.json")

	ollamaUrl := getOllamaUrl()
	fmt.Printf("🤖 Using Ollama embedding endpoint: %s\n", ollamaUrl)

	fmt.Printf("🔍 Indexing vault: %s\n", VAULT_PATH)

	if _, err := os.Stat(VAULT_PATH); os.IsNotExist(err) {
		fmt.Printf("❌ Vault path not found: %s\n", VAULT_PATH)
		os.Exit(1)
	}

	jobs := make(chan Job, 5000)
	results := make(chan *IndexEntry, 5000)
	var wg sync.WaitGroup
	var failed atomic.Int64

	numWorkers := 10 // Process 10 files concurrently
	for w := 1; w <= numWorkers; w++ {
		wg.Add(1)
		go worker(w, ollamaUrl, jobs, results, &failed, &wg)
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

	index := []*IndexEntry{}
	for entry := range results {
		index = append(index, entry)
	}

	// Keep the previous index when most of this run failed (Ollama down):
	// it would silently drop documents. A few bad files still update it.
	n := int(failed.Load())
	if len(index) == 0 || n > len(index) {
		fmt.Printf("❌ %d file(s) failed, %d embedded; index left unchanged\n", n, len(index))
		os.Exit(1)
	}

	if err := writeIndex(index); err != nil {
		fmt.Printf("❌ Writing %s: %v\n", INDEX_PATH, err)
		os.Exit(1)
	}

	fmt.Printf("✅ Index saved to %s (%d documents)\n", INDEX_PATH, len(index))
	if n > 0 {
		fmt.Printf("⚠️  %d file(s) skipped (see above)\n", n)
		os.Exit(1)
	}
}

func writeIndex(index []*IndexEntry) error {
	if err := os.MkdirAll(filepath.Dir(INDEX_PATH), 0755); err != nil {
		return err
	}
	// A unique temp file: overlapping runs must not write the same one.
	f, err := os.CreateTemp(filepath.Dir(INDEX_PATH), "semantic_index.*.tmp")
	if err != nil {
		return err
	}
	tmp := f.Name()
	err = json.NewEncoder(f).Encode(index)
	if err == nil {
		err = f.Chmod(0644)
	}
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err == nil {
		err = os.Rename(tmp, INDEX_PATH)
	}
	if err != nil {
		os.Remove(tmp)
	}
	return err
}
