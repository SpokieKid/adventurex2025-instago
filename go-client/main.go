package main

import (
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/adventurex2025-instago/go-client/database"
	"github.com/adventurex2025-instago/go-client/handlers"
	"github.com/adventurex2025-instago/go-client/models"
	"github.com/adventurex2025-instago/go-client/services"
)

func main() {
	// 加载配置
	config := loadConfig()

	// 初始化数据库
	db, err := database.NewDatabase(config.DBPath)
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer db.Close()

	// 初始化AI服务
	aiService, err := services.NewAIService(config)
	if err != nil {
		log.Fatalf("Failed to initialize AI service: %v", err)
	}

	// 初始化处理器
	handler := handlers.NewHandler(db, aiService)

	// 设置路由
	setupRoutes(handler)

	// 启动服务器
	port := config.Port
	if port == "" {
		port = "8080"
	}

	fmt.Printf("Server starting on port %s...\n", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

// 加载配置
func loadConfig() *models.Config {
	return &models.Config{
		QwenVLAPIKey:   getEnv("QWEN_VL_API_KEY", ""),
		QwenTextAPIKey: getEnv("QWEN_TEXT_API_KEY", ""),
		OpenAIAPIKey:   getEnv("OPENAI_API_KEY", ""),
		DBPath:         getEnv("DB_PATH", "./instago.db"),
		Port:           getEnv("PORT", "8080"),
	}
}

// 获取环境变量
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// 设置路由
func setupRoutes(handler *handlers.Handler) {
	// 设置CORS
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		// 设置CORS头
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

		// 处理预检请求
		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}

		// 根据路径分发请求
		switch {
		case r.URL.Path == "/upload":
			handler.UploadHandler(w, r)
		case r.URL.Path == "/search":
			handler.SearchHandler(w, r)
		case r.URL.Path == "/folders":
			handler.CreateOrUpdateFolderHandler(w, r)
		case r.URL.Path == "/folders/" || (len(r.URL.Path) > 9 && r.URL.Path[:9] == "/folders/"):
			if r.Method == "GET" {
				handler.GetFolderContentsHandler(w, r)
			} else if r.Method == "DELETE" {
				handler.DeleteFolderHandler(w, r)
			} else {
				http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			}
		case r.URL.Path == "/" || r.URL.Path == "/index.html":
			serveStaticFile(w, r, "frontend.html")
		case r.URL.Path == "/test.html":
			serveStaticFile(w, r, "test.html")
		default:
			http.NotFound(w, r)
		}
	})
}

// 服务静态文件
func serveStaticFile(w http.ResponseWriter, r *http.Request, filename string) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	http.ServeFile(w, r, filename)
}
