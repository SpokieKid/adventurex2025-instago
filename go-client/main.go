package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"

	_ "github.com/mattn/go-sqlite3"
	chromem "github.com/philippgille/chromem-go"
	"github.com/joho/godotenv"
)

// 数据模型
type Folder struct {
	ID    int    `json:"id" db:"id"`
	Name  string `json:"name" db:"name"`
	Upper int    `json:"upper" db:"upper"`
}

type Object struct {
	ID          int    `json:"id" db:"id"`
	Data        string `json:"data" db:"data"`
	Description string `json:"description" db:"description"`
	FolderID    int    `json:"folder_id" db:"folder_id"`
}

// API请求/响应结构
type UploadRequest struct {
	Image    string `json:"image"`     // base64编码的图片
	FolderID int    `json:"folder_id"` // 可选，指定文件夹
}

type SearchRequest struct {
	Query string `json:"query"`
	Limit int    `json:"limit,omitempty"`
}

type FolderRequest struct {
	Name  string `json:"name"`
	Upper int    `json:"upper"`
}

// 千问API响应结构
type QwenVLResponse struct {
	Output struct {
		Choices []struct {
			Message struct {
				Content []struct {
					Text string `json:"text"`
				} `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	} `json:"output"`
}

type QwenTextResponse struct {
	Output struct {
		Text string `json:"text"`
	} `json:"output"`
}

// 全局变量
var (
	db         *sql.DB
	vecDB      *chromem.DB
	collection *chromem.Collection
	config     Config
	ctx        = context.Background()
)

type Config struct {
	QwenVLAPIKey   string
	QwenTextAPIKey string
	OpenAIAPIKey   string
	DBPath         string
	Port           string
}

// 工具函数
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// 初始化SQLite数据库
func initDB() error {
	var err error
	db, err = sql.Open("sqlite3", config.DBPath)
	if err != nil {
		return err
	}

	// 创建表
	folderTable := `
	CREATE TABLE IF NOT EXISTS folders (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT NOT NULL,
		upper INTEGER DEFAULT 0
	);
	`

	objectTable := `
	CREATE TABLE IF NOT EXISTS objects (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		data TEXT NOT NULL,
		description TEXT NOT NULL,
		folder_id INTEGER DEFAULT 0
	);
	`

	if _, err := db.Exec(folderTable); err != nil {
		return err
	}

	if _, err := db.Exec(objectTable); err != nil {
		return err
	}

	// 创建根文件夹（如果不存在）
	var count int
	err = db.QueryRow("SELECT COUNT(*) FROM folders WHERE id = 0").Scan(&count)
	if err == nil && count == 0 {
		_, err = db.Exec("INSERT INTO folders (id, name, upper) VALUES (0, 'Root', 0)")
	}

	return err
}

// 初始化向量数据库
func initVectorDB() error {
	vecDB = chromem.NewDB()

	// 创建或获取collection，使用本地默认嵌入函数
	var err error
	var embeddingFunc chromem.EmbeddingFunc

	// 优先尝试使用Ollama嵌入函数（如果Ollama服务可用）
	embeddingFunc = chromem.NewEmbeddingFuncOllama("nomic-embed-text", "http://localhost:11434/api")

	collection, err = vecDB.GetOrCreateCollection("instago", nil, embeddingFunc)
	return err
}

// HTTP处理器

// 上传图片处理器
func uploadHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req UploadRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request format", http.StatusBadRequest)
		return
	}

	if req.Image == "" {
		http.Error(w, "Image data is required", http.StatusBadRequest)
		return
	}

	// 调用千问视觉模型分析图片
	description, err := analyzeImageWithQwenVL(req.Image)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to analyze image: %v", err), http.StatusInternalServerError)
		return
	}

	// 获取文件夹树信息
	folderTree, err := getFolderTree()
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to get folder tree: %v", err), http.StatusInternalServerError)
		return
	}

	// 调用千问文本模型获取摘要和推荐文件夹
	digest, recommendedFolderID, err := processWithQwenText(description, folderTree, req.FolderID)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to process with text model: %v", err), http.StatusInternalServerError)
		return
	}

	// 创建Object并存储到数据库
	objectID, err := createObject(req.Image, description, recommendedFolderID)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to create object: %v", err), http.StatusInternalServerError)
		return
	}

	// 将摘要向量化并存储到向量数据库
	if err := storeInVectorDB(objectID, digest); err != nil {
		http.Error(w, fmt.Sprintf("Failed to store in vector database: %v", err), http.StatusInternalServerError)
		return
	}

	response := map[string]interface{}{
		"object_id":   objectID,
		"description": description,
		"digest":      digest,
		"folder_id":   recommendedFolderID,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// 语义搜索处理器
func searchHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req SearchRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request format", http.StatusBadRequest)
		return
	}

	if req.Query == "" {
		http.Error(w, "Query is required", http.StatusBadRequest)
		return
	}

	if req.Limit <= 0 {
		req.Limit = 10
	}

	// 检查集合中的文档数量，避免请求数量超过实际文档数量
	docCount := collection.Count()
	if req.Limit > docCount {
		req.Limit = docCount
	}

	// 如果集合为空，直接返回空结果
	if docCount == 0 {
		response := map[string]interface{}{
			"results": []Object{},
			"count":   0,
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(response)
		return
	}

	// 在向量数据库中搜索
	results, err := collection.Query(ctx, req.Query, req.Limit, nil, nil)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to search: %v", err), http.StatusInternalServerError)
		return
	}

	// 根据搜索结果获取Object详情
	var objects []Object
	for _, result := range results {
		objectID, err := strconv.Atoi(result.ID)
		if err != nil {
			continue
		}

		obj, err := getObjectByID(objectID)
		if err != nil {
			continue
		}

		objects = append(objects, obj)
	}

	response := map[string]interface{}{
		"results": objects,
		"count":   len(objects),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// 创建或更新文件夹处理器
func createOrUpdateFolderHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req FolderRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request format", http.StatusBadRequest)
		return
	}

	if req.Name == "" {
		http.Error(w, "Folder name is required", http.StatusBadRequest)
		return
	}

	// 检查是否为更新操作（通过查询参数id）
	idParam := r.URL.Query().Get("id")
	if idParam != "" {
		// 更新文件夹
		id, err := strconv.Atoi(idParam)
		if err != nil {
			http.Error(w, "Invalid folder ID", http.StatusBadRequest)
			return
		}

		err = updateFolder(id, req.Name, req.Upper)
		if err != nil {
			http.Error(w, fmt.Sprintf("Failed to update folder: %v", err), http.StatusInternalServerError)
			return
		}

		response := map[string]interface{}{
			"message": "Folder updated successfully",
			"id":      id,
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(response)
	} else {
		// 创建新文件夹
		id, err := createFolder(req.Name, req.Upper)
		if err != nil {
			http.Error(w, fmt.Sprintf("Failed to create folder: %v", err), http.StatusInternalServerError)
			return
		}

		response := map[string]interface{}{
			"message": "Folder created successfully",
			"id":      id,
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(response)
	}
}

// 获取文件夹内容处理器
func getFolderContentsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// 从URL路径中提取文件夹ID
	path := strings.TrimPrefix(r.URL.Path, "/folders/")
	folderID, err := strconv.Atoi(path)
	if err != nil {
		folderID = 0 // 默认为根文件夹
	}

	// 获取子文件夹
	subFolders, err := getSubFolders(folderID)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to get subfolders: %v", err), http.StatusInternalServerError)
		return
	}

	// 获取文件夹中的对象
	objects, err := getObjectsInFolder(folderID)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to get objects: %v", err), http.StatusInternalServerError)
		return
	}

	response := map[string]interface{}{
		"folder_id":   folderID,
		"subfolders":  subFolders,
		"objects":     objects,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// 删除文件夹处理器
func deleteFolderHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != "DELETE" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// 从URL路径中提取文件夹ID
	path := strings.TrimPrefix(r.URL.Path, "/folders/")
	folderID, err := strconv.Atoi(path)
	if err != nil {
		http.Error(w, "Invalid folder ID", http.StatusBadRequest)
		return
	}

	if folderID == 0 {
		http.Error(w, "Cannot delete root folder", http.StatusBadRequest)
		return
	}

	err = deleteFolder(folderID)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to delete folder: %v", err), http.StatusInternalServerError)
		return
	}

	response := map[string]string{
		"message": "Folder deleted successfully",
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// 加载配置
func loadConfig() Config {
	// 加载.env文件
	godotenv.Load()

	return Config{
		QwenVLAPIKey:   getEnv("QWEN_VL_API_KEY", ""),
		QwenTextAPIKey: getEnv("QWEN_TEXT_API_KEY", ""),
		OpenAIAPIKey:   getEnv("OPENAI_API_KEY", ""),
		DBPath:         getEnv("DB_PATH", "./instago.db"),
		Port:           getEnv("PORT", "8080"),
	}
}

// 设置路由
func setupRoutes() {
	// 设置CORS中间件
	corsHandler := func(next http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Access-Control-Allow-Origin", "*")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

			if r.Method == "OPTIONS" {
				w.WriteHeader(http.StatusOK)
				return
			}

			next(w, r)
		}
	}

	// 注册路由
	http.HandleFunc("/upload", corsHandler(uploadHandler))
	http.HandleFunc("/search", corsHandler(searchHandler))
	http.HandleFunc("/folders", corsHandler(createOrUpdateFolderHandler))
	http.HandleFunc("/folders/", corsHandler(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == "GET" {
			getFolderContentsHandler(w, r)
		} else if r.Method == "DELETE" {
			deleteFolderHandler(w, r)
		} else {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		}
	}))

	// 静态文件服务
	http.HandleFunc("/", corsHandler(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/" || r.URL.Path == "/index.html" {
			http.ServeFile(w, r, "frontend.html")
		} else if r.URL.Path == "/test.html" {
			http.ServeFile(w, r, "test.html")
		} else {
			http.NotFound(w, r)
		}
	}))
}

func main() {
	// 加载配置
	config = loadConfig()

	// 初始化数据库
	if err := initDB(); err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer db.Close()

	// 初始化向量数据库
	if err := initVectorDB(); err != nil {
		log.Fatalf("Failed to initialize vector database: %v", err)
	}

	// 设置路由
	setupRoutes()

	// 启动服务器
	port := config.Port
	if port == "" {
		port = "8080"
	}

	fmt.Printf("🚀 InstaGo 服务器启动成功！\n")
	fmt.Printf("📍 服务地址: http://localhost:%s\n", port)
	fmt.Printf("📊 数据库路径: %s\n", config.DBPath)
	
	if config.QwenVLAPIKey != "" {
		fmt.Printf("🤖 千问视觉模型: 已配置\n")
	} else {
		fmt.Printf("🤖 千问视觉模型: 模拟模式\n")
	}
	
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
