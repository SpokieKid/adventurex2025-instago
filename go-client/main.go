package main

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"os"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
	_ "github.com/mattn/go-sqlite3"
	chromem "github.com/philippgille/chromem-go"
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

	// // 使用默认嵌入函数（本地计算，无需外部服务）
	// embeddingFunc = chromem.NewEmbeddingFuncDefault()

	// 优先尝试使用Ollama嵌入函数（如果Ollama服务可用）
	embeddingFunc = chromem.NewEmbeddingFuncOllama("nomic-embed-text", "http://localhost:11434/api")

	// 如果有OpenAI API密钥且需要使用，可以取消注释以下代码
	// if config.OpenAIAPIKey != "" {
	//		embeddingFunc = chromem.NewEmbeddingFuncOpenAI(config.OpenAIAPIKey, chromem.EmbeddingModelOpenAI3Small)
	// }

	collection, err = vecDB.GetOrCreateCollection("instago", nil, embeddingFunc)
	return err
}

// 上传图片处理器
func uploadHandler(c *gin.Context) {
	var req UploadRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid request format"})
		return
	}

	if req.Image == "" {
		c.JSON(400, gin.H{"error": "Image data is required"})
		return
	}

	// 调用千问视觉模型分析图片
	description, err := analyzeImageWithQwenVL(req.Image)
	if err != nil {
		c.JSON(500, gin.H{"error": fmt.Sprintf("Failed to analyze image: %v", err)})
		return
	}

	// 获取文件夹树信息
	folderTree, err := getFolderTree()
	if err != nil {
		c.JSON(500, gin.H{"error": fmt.Sprintf("Failed to get folder tree: %v", err)})
		return
	}

	// 调用千问文本模型获取摘要和推荐文件夹
	digest, recommendedFolderID, err := processWithQwenText(description, folderTree, req.FolderID)
	if err != nil {
		c.JSON(500, gin.H{"error": fmt.Sprintf("Failed to process with text model: %v", err)})
		return
	}

	// 创建Object并存储到数据库
	objectID, err := createObject(req.Image, description, recommendedFolderID)
	if err != nil {
		c.JSON(500, gin.H{"error": fmt.Sprintf("Failed to create object: %v", err)})
		return
	}

	// 将摘要向量化并存储到向量数据库
	if err := storeInVectorDB(objectID, digest); err != nil {
		c.JSON(500, gin.H{"error": fmt.Sprintf("Failed to store in vector database: %v", err)})
		return
	}

	c.JSON(200, gin.H{
		"object_id":   objectID,
		"description": description,
		"digest":      digest,
		"folder_id":   recommendedFolderID,
	})
}

// 语义搜索处理器
func searchHandler(c *gin.Context) {
	var req SearchRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid request format"})
		return
	}

	if req.Query == "" {
		c.JSON(400, gin.H{"error": "Query is required"})
		return
	}

	if req.Limit <= 0 {
		req.Limit = 10
	}

	// 检查集合中的文档数量，避免请求数量超过实际文档数量
	ctx := context.Background()
	docCount := collection.Count()
	if req.Limit > docCount {
		req.Limit = docCount
	}

	// 如果集合为空，直接返回空结果
	if docCount == 0 {
		c.JSON(200, gin.H{
			"results": []Object{},
			"count":   0,
		})
		return
	}

	// 在向量数据库中搜索
	results, err := collection.Query(ctx, req.Query, req.Limit, nil, nil)
	if err != nil {
		c.JSON(500, gin.H{"error": fmt.Sprintf("Failed to search: %v", err)})
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

	c.JSON(200, gin.H{
		"results": objects,
		"count":   len(objects),
	})
}

// 创建或更新文件夹处理器
func createOrUpdateFolderHandler(c *gin.Context) {
	var req FolderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid request format"})
		return
	}

	if req.Name == "" {
		c.JSON(400, gin.H{"error": "Folder name is required"})
		return
	}

	// 检查是否为更新操作（通过查询参数id）
	idParam := c.Query("id")
	if idParam != "" {
		// 更新文件夹
		id, err := strconv.Atoi(idParam)
		if err != nil {
			c.JSON(400, gin.H{"error": "Invalid folder ID"})
			return
		}

		err = updateFolder(id, req.Name, req.Upper)
		if err != nil {
			c.JSON(500, gin.H{"error": fmt.Sprintf("Failed to update folder: %v", err)})
			return
		}

		c.JSON(200, gin.H{"message": "Folder updated successfully", "id": id})
	} else {
		// 创建新文件夹
		id, err := createFolder(req.Name, req.Upper)
		if err != nil {
			c.JSON(500, gin.H{"error": fmt.Sprintf("Failed to create folder: %v", err)})
			return
		}

		c.JSON(200, gin.H{"message": "Folder created successfully", "id": id})
	}
}

// 获取文件夹内容处理器
func getFolderContentsHandler(c *gin.Context) {
	idParam := c.Param("id")
	id, err := strconv.Atoi(idParam)
	if err != nil {
		c.JSON(400, gin.H{"error": "Invalid folder ID"})
		return
	}

	// 获取子文件夹
	subFolders, err := getSubFolders(id)
	if err != nil {
		c.JSON(500, gin.H{"error": fmt.Sprintf("Failed to get subfolders: %v", err)})
		return
	}

	// 获取文件夹中的对象
	objects, err := getObjectsInFolder(id)
	if err != nil {
		c.JSON(500, gin.H{"error": fmt.Sprintf("Failed to get objects: %v", err)})
		return
	}

	c.JSON(200, gin.H{
		"subfolders": subFolders,
		"objects":    objects,
	})
}

// 删除文件夹处理器
func deleteFolderHandler(c *gin.Context) {
	idParam := c.Param("id")
	id, err := strconv.Atoi(idParam)
	if err != nil {
		c.JSON(400, gin.H{"error": "Invalid folder ID"})
		return
	}

	err = deleteFolder(id)
	if err != nil {
		c.JSON(500, gin.H{"error": fmt.Sprintf("Failed to delete folder: %v", err)})
		return
	}

	c.JSON(200, gin.H{"message": "Folder deleted successfully"})
}

func main() {
	// 加载环境变量
	if err := godotenv.Load(".env"); err != nil {
		log.Printf("Warning: .env file not found: %v", err)
	}

	// 初始化配置
	config = Config{
		QwenVLAPIKey:   getEnv("QWEN_VL_API_KEY", ""),
		QwenTextAPIKey: getEnv("QWEN_TEXT_API_KEY", ""),
		OpenAIAPIKey:   getEnv("OPENAI_API_KEY", ""),
		DBPath:         getEnv("DB_PATH", "./instago.db"),
		Port:           getEnv("PORT", "8080"),
	}

	// 初始化数据库
	if err := initDB(); err != nil {
		log.Fatal("Failed to initialize database:", err)
	}
	defer db.Close()

	// 初始化向量数据库
	if err := initVectorDB(); err != nil {
		log.Fatal("Failed to initialize vector database:", err)
	}

	// 设置路由
	router := gin.Default()

	// 添加CORS中间件
	router.Use(func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	})

	// 静态文件服务
	router.Static("/static", "./")
	router.StaticFile("/", "./frontend.html")
	router.StaticFile("/frontend.html", "./frontend.html")
	router.StaticFile("/test.html", "./test.html")

	// 健康检查
	router.GET("/ping", func(c *gin.Context) {
		c.JSON(200, gin.H{"message": "pong"})
	})

	// 主要接口
	router.POST("/upload", uploadHandler)
	router.POST("/search", searchHandler)

	// 文件夹管理接口
	router.POST("/folder", createOrUpdateFolderHandler)
	router.GET("/folder/:id", getFolderContentsHandler)
	router.DELETE("/folder/:id", deleteFolderHandler)

	log.Printf("Server starting on port %s", config.Port)
	router.Run(":" + config.Port)
}
