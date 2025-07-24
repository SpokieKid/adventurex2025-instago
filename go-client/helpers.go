package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	chromem "github.com/philippgille/chromem-go"
)

// AI模型调用相关函数

// analyzeImageWithQwenVL 使用千问视觉模型分析图片
func analyzeImageWithQwenVL(base64Image string) (string, error) {
	if config.QwenVLAPIKey == "" {
		// 模拟模式
		return generateMockDescription(), nil
	}

	// 构建请求体
	requestBody := map[string]interface{}{
		"model": "qwen-vl-max",
		"input": map[string]interface{}{
			"messages": []map[string]interface{}{
				{
					"role": "user",
					"content": []map[string]interface{}{
						{
							"image": "data:image/jpeg;base64," + base64Image,
						},
						{
							"text": "请详细描述这张图片的内容，包括主要物体、场景、人物、动作、颜色、构图等细节，用markdown格式返回。",
						},
					},
				},
			},
		},
	}

	jsonData, err := json.Marshal(requestBody)
	if err != nil {
		return "", fmt.Errorf("序列化请求失败: %v", err)
	}

	// 发送请求
	req, err := http.NewRequest("POST", "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation", bytes.NewBuffer(jsonData))
	if err != nil {
		return "", fmt.Errorf("创建请求失败: %v", err)
	}

	req.Header.Set("Authorization", "Bearer "+config.QwenVLAPIKey)
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("请求失败: %v", err)
	}
	defer resp.Body.Close()

	var response QwenVLResponse
	if err := json.NewDecoder(resp.Body).Decode(&response); err != nil {
		return "", fmt.Errorf("解析响应失败: %v", err)
	}

	if len(response.Output.Choices) > 0 && len(response.Output.Choices[0].Message.Content) > 0 {
		return response.Output.Choices[0].Message.Content[0].Text, nil
	}

	return "", fmt.Errorf("千问视觉模型返回空结果")
}

// processWithQwenText 使用千问文本模型处理图片描述
func processWithQwenText(description, folderTree string, suggestedFolderID int) (string, int, error) {
	if config.QwenTextAPIKey == "" {
		// 模拟模式
		digest := generateMockDigest(description)
		return digest, suggestedFolderID, nil
	}

	prompt := fmt.Sprintf(`基于以下图片描述和文件夹结构，请：
1. 生成一个简洁的图片摘要（1-2句话）
2. 推荐最适合的文件夹ID

图片描述：
%s

文件夹结构：
%s

建议的文件夹ID：%d

请以JSON格式返回：{"digest": "摘要", "folder_id": 推荐的文件夹ID}`, description, folderTree, suggestedFolderID)

	requestBody := map[string]interface{}{
		"model": "qwen-turbo",
		"input": map[string]interface{}{
			"messages": []map[string]interface{}{
				{
					"role": "user",
					"content": prompt,
				},
			},
		},
	}

	jsonData, err := json.Marshal(requestBody)
	if err != nil {
		return "", suggestedFolderID, fmt.Errorf("序列化请求失败: %v", err)
	}

	req, err := http.NewRequest("POST", "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation", bytes.NewBuffer(jsonData))
	if err != nil {
		return "", suggestedFolderID, fmt.Errorf("创建请求失败: %v", err)
	}

	req.Header.Set("Authorization", "Bearer "+config.QwenTextAPIKey)
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return "", suggestedFolderID, fmt.Errorf("请求失败: %v", err)
	}
	defer resp.Body.Close()

	var response QwenTextResponse
	if err := json.NewDecoder(resp.Body).Decode(&response); err != nil {
		return "", suggestedFolderID, fmt.Errorf("解析响应失败: %v", err)
	}

	// 尝试解析JSON响应
	var result map[string]interface{}
	if err := json.Unmarshal([]byte(response.Output.Text), &result); err == nil {
		if digest, ok := result["digest"].(string); ok {
			if folderID, ok := result["folder_id"].(float64); ok {
				return digest, int(folderID), nil
			}
		}
	}

	// 如果解析失败，返回原始文本作为摘要
	return response.Output.Text, suggestedFolderID, nil
}

// 数据库操作相关函数

// createObject 创建图片对象
func createObject(data, description string, folderID int) (int, error) {
	query := "INSERT INTO objects (data, description, folder_id) VALUES (?, ?, ?)"
	result, err := db.Exec(query, data, description, folderID)
	if err != nil {
		return 0, err
	}

	id, err := result.LastInsertId()
	if err != nil {
		return 0, err
	}

	return int(id), nil
}

// getObjectByID 根据ID获取图片对象
func getObjectByID(id int) (Object, error) {
	var obj Object
	query := "SELECT id, data, description, folder_id FROM objects WHERE id = ?"
	err := db.QueryRow(query, id).Scan(&obj.ID, &obj.Data, &obj.Description, &obj.FolderID)
	return obj, err
}

// createFolder 创建文件夹
func createFolder(name string, upper int) (int, error) {
	query := "INSERT INTO folders (name, upper) VALUES (?, ?)"
	result, err := db.Exec(query, name, upper)
	if err != nil {
		return 0, err
	}

	id, err := result.LastInsertId()
	if err != nil {
		return 0, err
	}

	return int(id), nil
}

// updateFolder 更新文件夹
func updateFolder(id int, name string, upper int) error {
	query := "UPDATE folders SET name = ?, upper = ? WHERE id = ?"
	_, err := db.Exec(query, name, upper, id)
	return err
}

// deleteFolder 删除文件夹
func deleteFolder(id int) error {
	// 先删除文件夹中的对象
	_, err := db.Exec("DELETE FROM objects WHERE folder_id = ?", id)
	if err != nil {
		return err
	}

	// 删除子文件夹
	_, err = db.Exec("DELETE FROM folders WHERE upper = ?", id)
	if err != nil {
		return err
	}

	// 删除文件夹本身
	_, err = db.Exec("DELETE FROM folders WHERE id = ?", id)
	return err
}

// getSubFolders 获取子文件夹
func getSubFolders(parentID int) ([]Folder, error) {
	var folders []Folder
	query := "SELECT id, name, upper FROM folders WHERE upper = ?"
	rows, err := db.Query(query, parentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var folder Folder
		if err := rows.Scan(&folder.ID, &folder.Name, &folder.Upper); err != nil {
			return nil, err
		}
		folders = append(folders, folder)
	}

	return folders, nil
}

// getObjectsInFolder 获取文件夹中的对象
func getObjectsInFolder(folderID int) ([]Object, error) {
	var objects []Object
	query := "SELECT id, data, description, folder_id FROM objects WHERE folder_id = ?"
	rows, err := db.Query(query, folderID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var obj Object
		if err := rows.Scan(&obj.ID, &obj.Data, &obj.Description, &obj.FolderID); err != nil {
			return nil, err
		}
		objects = append(objects, obj)
	}

	return objects, nil
}

// getFolderTree 获取文件夹树结构
func getFolderTree() (string, error) {
	folders, err := getAllFolders()
	if err != nil {
		return "", err
	}

	var tree strings.Builder
	tree.WriteString("文件夹结构：\n")
	for _, folder := range folders {
		if folder.Upper == 0 {
			tree.WriteString(fmt.Sprintf("- [%d] %s\n", folder.ID, folder.Name))
		} else {
			tree.WriteString(fmt.Sprintf("  - [%d] %s (父文件夹: %d)\n", folder.ID, folder.Name, folder.Upper))
		}
	}

	return tree.String(), nil
}

// getAllFolders 获取所有文件夹
func getAllFolders() ([]Folder, error) {
	var folders []Folder
	query := "SELECT id, name, upper FROM folders ORDER BY upper, id"
	rows, err := db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var folder Folder
		if err := rows.Scan(&folder.ID, &folder.Name, &folder.Upper); err != nil {
			return nil, err
		}
		folders = append(folders, folder)
	}

	return folders, nil
}

// 向量数据库操作

// storeInVectorDB 将摘要存储到向量数据库
func storeInVectorDB(objectID int, digest string) error {
	// 使用正确的chromem.Document格式
	document := chromem.Document{
		ID:      fmt.Sprintf("%d", objectID),
		Content: digest,
	}

	return collection.AddDocument(ctx, document)
}

// 模拟函数（当API密钥未配置时使用）

// generateMockDescription 生成模拟的图片描述
func generateMockDescription() string {
	return `# 图片描述

这是一张通过模拟模式生成的图片描述。

## 主要内容
- 包含各种视觉元素
- 色彩丰富的构图
- 清晰的图像质量

## 建议
请配置千问视觉模型API密钥以获得真实的AI分析结果。`
}

// generateMockDigest 生成模拟的图片摘要
func generateMockDigest(description string) string {
	// 简单地从描述中提取前几个词作为摘要
	words := strings.Fields(description)
	if len(words) > 10 {
		return strings.Join(words[:10], " ") + "..."
	}
	return description
} 