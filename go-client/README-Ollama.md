# Ollama 嵌入服务部署指南

本指南介绍如何使用 Docker Compose 部署 Ollama 服务来解决向量数据库的嵌入问题。

## 🚀 快速开始

### 1. 启动 Ollama 服务

```bash
docker-compose up -d ollama

services:
  ollama:
    image: ollama/ollama:latest
    container_name: instago-ollama
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    environment:
      - OLLAMA_HOST=0.0.0.0
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

volumes:
   ollama_data:
    driver: local
```

### 2. 拉取嵌入模型

```bash
# 拉取推荐的嵌入模型
docker exec instago-ollama ollama pull nomic-embed-text
```

### 3. 测试嵌入服务

```bash
# 测试 API 是否正常工作
curl http://localhost:11434/api/embeddings -d '{
  "model": "nomic-embed-text",
  "prompt": "测试文本嵌入"
}'
```

### 4. 启动 Go 应用

```bash
cd go-client
go run main.go helpers.go
```

## 📋 配置说明

### Docker Compose 配置

- **端口**: Ollama 服务运行在 `11434` 端口
- **数据持久化**: 模型数据存储在 `ollama_data` 卷中
- **健康检查**: 自动检查服务状态
- **GPU 支持**: 可选的 GPU 配置（需要 NVIDIA Docker 支持）

### 嵌入模型选择

| 模型名称 | 维度 | 大小 | 特点 |
|---------|------|------|------|
| `nomic-embed-text` | 768 | ~274MB | 高质量文本嵌入，推荐使用 |
| `all-minilm` | 384 | ~23MB | 轻量级模型，速度快 |
| `mxbai-embed-large` | 1024 | ~669MB | 大型模型，精度更高 |

## 🔧 Go 代码集成

代码已自动配置使用 Ollama 嵌入函数：

```go
// 使用 Ollama 嵌入函数
embeddingFunc = chromem.NewEmbeddingFuncOllama("nomic-embed-text", "http://localhost:11434/api")
```

### 切换嵌入模型

如果需要使用不同的模型，修改 `main.go` 中的模型名称：

```go
// 使用大型模型
embeddingFunc = chromem.NewEmbeddingFuncOllama("mxbai-embed-large", "http://localhost:11434/api")
```

## 🛠️ 故障排除

### 常见问题

1. **Ollama 服务无法启动**
   ```bash
   # 检查 Docker 状态
   docker-compose logs ollama
   
   # 重启服务
   docker-compose restart ollama
   ```

2. **模型下载失败**
   ```bash
   # 检查网络连接
   docker exec instago-ollama ollama list
   
   # 手动拉取模型
   docker exec -it instago-ollama ollama pull nomic-embed-text
   ```

3. **嵌入 API 调用失败**
   ```bash
   # 检查服务状态
   curl http://localhost:11434/api/tags
   
   # 测试嵌入 API
   curl http://localhost:11434/api/embeddings -d '{
     "model": "nomic-embed-text",
     "prompt": "test"
   }'
   ```

### 回退方案

如果 Ollama 服务不可用，可以在 `main.go` 中启用默认嵌入函数：

```go
// 回退到默认嵌入函数
embeddingFunc = chromem.NewEmbeddingFuncDefault()
```

## 🔄 服务管理

```bash
# 启动服务
docker-compose up -d ollama

# 停止服务
docker-compose down

# 查看日志
docker-compose logs -f ollama

# 重启服务
docker-compose restart ollama

# 清理数据（谨慎使用）
docker-compose down -v
```

## 🎯 性能优化

### GPU 加速

如果有 NVIDIA GPU，可以启用 GPU 支持：

1. 安装 NVIDIA Docker 支持
2. 在 `docker-compose.yml` 中取消注释 GPU 配置
3. 使用 `ollama-gpu` 服务替代 `ollama`

### 内存优化

- 选择合适大小的嵌入模型
- 根据服务器配置调整 Docker 内存限制
- 考虑使用模型量化版本

## 📊 监控和日志

```bash
# 实时查看服务状态
docker stats instago-ollama

# 查看详细日志
docker logs -f instago-ollama

# 检查模型列表
docker exec instago-ollama ollama list
```

---

**注意**: 首次启动时需要下载模型，可能需要几分钟时间。请确保网络连接稳定。