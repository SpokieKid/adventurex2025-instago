# InstaGo - 智能图片管理和语义搜索系统

一个基于Go语言开发的智能图片管理系统，集成了AI图片分析、语义搜索和文件夹管理功能。

## 🌟 主要功能

### 核心接口
1. **图片上传分析** (`/upload`) - 上传图片并使用千问视觉模型进行智能分析
2. **语义搜索** (`/search`) - 通过自然语言描述搜索相关图片

### 辅助接口
3. **文件夹管理** (`/folder`) - 创建和修改文件夹结构
4. **文件夹内容查询** (`/folder/:id`) - 获取指定文件夹下的子文件夹和图片对象

## 🏗️ 系统架构

### 数据模型
- **Folder**: 文件夹信息 (ID, name, upper)
- **Object**: 图片对象 (ID, data, description, folderID)
- **向量数据库**: 存储图片摘要的向量化数据，支持语义搜索

### 技术栈
- **后端框架**: Gin (Go)
- **数据库**: SQLite (结构化数据)
- **向量数据库**: chromem-go (语义搜索)
- **AI模型**: 
  - 千问视觉模型 (QWEN-VL-MAX) - 图片分析
  - 千问文本模型 (QWEN-TURBO) - 文本处理
  - OpenAI Embeddings - 向量化

## 🚀 快速开始

### 1. 环境配置

编辑 `.env` 文件，配置API密钥：

```env
# 千问视觉模型API密钥
QWEN_VL_API_KEY=your_qwen_vl_api_key_here

# 千问文本模型API密钥
QWEN_TEXT_API_KEY=your_qwen_text_api_key_here

# OpenAI API密钥（用于向量数据库）
OPENAI_API_KEY=your_openai_api_key_here

# 数据库配置
DB_PATH=./instago.db

# 服务器配置
PORT=8080
```

### 2. 编译和运行

```bash
cd go-client
go mod tidy
go build -o instago
./instago
```

服务器将在 `http://localhost:8080` 启动。

### 3. 测试功能

打开 `test.html` 文件在浏览器中测试各项功能：
- 图片上传和分析
- 语义搜索
- 文件夹管理
- 系统状态检查

## 📡 API 接口文档

### 1. 上传图片 `POST /upload`

**请求体**:
```json
{
  "image": "base64编码的图片数据",
  "folder_id": 1  // 可选，指定存储文件夹
}
```

**响应**:
```json
{
  "object_id": 123,
  "description": "图片的详细描述（markdown格式）",
  "digest": "图片摘要",
  "folder_id": 1
}
```

### 2. 语义搜索 `POST /search`

**请求体**:
```json
{
  "query": "蓝色的天空",
  "limit": 10  // 可选，默认10
}
```

**响应**:
```json
{
  "results": [
    {
      "id": 123,
      "data": "base64图片数据",
      "description": "图片描述",
      "folder_id": 1
    }
  ],
  "count": 1
}
```

### 3. 文件夹管理

**创建文件夹** `POST /folder`:
```json
{
  "name": "风景照片",
  "upper": 0  // 父文件夹ID，0表示根文件夹
}
```

**响应**:
```json
{
  "message": "Folder created successfully",
  "id": 新文件夹ID
}
```

**更新文件夹** `POST /folder?id=文件夹ID`:
```json
{
  "name": "新名称",
  "upper": 1
}
```

**响应**:
```json
{
  "message": "Folder updated successfully",
  "id": 文件夹ID
}
```

**删除文件夹** `DELETE /folder/:id`:

**响应**:
```json
{
  "message": "Folder deleted successfully"
}
```

### 4. 获取文件夹内容 `GET /folder/:id`

**响应**:
```json
{
  "subfolders": [
    {
      "id": 2,
      "name": "子文件夹",
      "upper": 1
    }
  ],
  "objects": [
    {
      "id": 123,
      "data": "base64图片数据",
      "description": "图片描述",
      "folder_id": 1
    }
  ]
}
```

## 🔄 工作流程

1. **图片上传**: 用户上传图片 → 千问视觉模型分析 → 生成markdown描述
2. **智能分类**: 结合文件夹树信息 → 千问文本模型处理 → 生成摘要和推荐文件夹
3. **数据存储**: 创建Object存储到SQLite → 向量化摘要存储到chromem-go
4. **语义搜索**: 用户查询 → 向量搜索匹配 → 返回相关图片对象

## 🛠️ 开发说明

### 项目结构
```
├── go-client/
│   ├── main.go          # 主程序和API路由
│   ├── helpers.go       # 辅助函数和AI模型调用
│   ├── go.mod          # Go模块依赖
│   └── go.sum          # 依赖校验
├── .env                # 环境变量配置
├── test.html           # 功能测试页面
├── README.md           # 项目文档
└── make.sh            # 构建脚本
```

### 主要依赖
- `github.com/gin-gonic/gin` - Web框架
- `github.com/mattn/go-sqlite3` - SQLite数据库驱动
- `github.com/philippgille/chromem-go` - 向量数据库
- `github.com/joho/godotenv` - 环境变量加载

### 模拟模式
如果未配置API密钥，系统将运行在模拟模式下：
- 图片分析返回模拟描述
- 文本处理返回简化摘要
- 向量搜索使用默认嵌入函数

## 🔧 构建和部署

### 本地开发
```bash
go run *.go
```

### 生产构建
```bash
# Linux/Windows
go build -o instago

# macOS (Apple Silicon)
GOOS=darwin GOARCH=arm64 go build -o instago-mac-silicon
```

## 📝 注意事项

1. **API密钥安全**: 请妥善保管API密钥，不要提交到版本控制系统
2. **数据库备份**: SQLite数据库文件包含所有图片数据，请定期备份
3. **性能优化**: 大量图片时建议使用专业的向量数据库如Pinecone或Weaviate
4. **CORS配置**: 当前允许所有来源访问，生产环境请配置适当的CORS策略

## 🤝 贡献

欢迎提交Issue和Pull Request来改进这个项目！

## 📄 许可证

MIT License