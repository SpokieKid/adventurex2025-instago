package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"

	chromem "github.com/philippgille/chromem-go"
)

// 千问视觉模型分析图片
func analyzeImageWithQwenVL(imageBase64 string) (string, error) {
	if config.QwenVLAPIKey == "" {
		return "Mock description: This is a sample image description for testing purposes.", nil
	}

	// 构建请求体
	requestBody := map[string]interface{}{
		"model": "qwen-vl-plus",
		"input": map[string]interface{}{
			"messages": []map[string]interface{}{
				{
					"role": "user",
					"content": []map[string]interface{}{
						{
							"image": "data:image/jpeg;base64," + imageBase64,
						},
						{
							"text": "请详细描述这张图片的内容",
						},
					},
				},
			},
		},
	}

	jsonData, err := json.Marshal(requestBody)
	if err != nil {
		fmt.Printf("JSON Marshal error: %v\n", err)
		return "", err
	}

	fmt.Printf("Calling Qwen VL API with key: %s...\n", config.QwenVLAPIKey[:10])

	req, err := http.NewRequest("POST", "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation", bytes.NewBuffer(jsonData))
	if err != nil {
		fmt.Printf("HTTP Request creation error: %v\n", err)
		return "", err
	}

	req.Header.Set("Authorization", "Bearer "+config.QwenVLAPIKey)
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("HTTP Request error: %v\n", err)
		return "", err
	}
	defer resp.Body.Close()

	fmt.Printf("API Response Status: %s\n", resp.Status)

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		fmt.Printf("Response body read error: %v\n", err)
		return "", err
	}

	fmt.Printf("API Response Body: %s\n", string(body))

	var response QwenVLResponse
	if err := json.Unmarshal(body, &response); err != nil {
		fmt.Printf("JSON Unmarshal error: %v\n", err)
		return "", err
	}

	if len(response.Output.Choices) == 0 {
		fmt.Printf("No choices in response: %+v\n", response)
		return "", fmt.Errorf("no response from Qwen VL model")
	}

	// 提取文本内容
	content := response.Output.Choices[0].Message.Content
	if len(content) == 0 {
		return "", fmt.Errorf("no content in response")
	}

	return content[0].Text, nil
}

// 获取文件夹树
func getFolderTree() (string, error) {
	rows, err := db.Query("SELECT id, name, upper FROM folders ORDER BY upper, id")
	if err != nil {
		return "", err
	}
	defer rows.Close()

	var folders []Folder
	for rows.Next() {
		var folder Folder
		if err := rows.Scan(&folder.ID, &folder.Name, &folder.Upper); err != nil {
			continue
		}
		folders = append(folders, folder)
	}

	// 构建树形结构的字符串表示
	var builder strings.Builder
	builder.WriteString("文件夹结构:\n")
	for _, folder := range folders {
		indent := strings.Repeat("  ", getDepth(folder.ID, folders))
		builder.WriteString(fmt.Sprintf("%s- %s (ID: %d)\n", indent, folder.Name, folder.ID))
	}

	return builder.String(), nil
}

// 计算文件夹深度
func getDepth(folderID int, folders []Folder) int {
	if folderID == 0 {
		return 0
	}

	for _, folder := range folders {
		if folder.ID == folderID {
			return 1 + getDepth(folder.Upper, folders)
		}
	}
	return 0
}

// 搜索内容结构体
type SearchContent struct {
	Name      string
	Digest    string
	FolderID  int
	Keywords  string
	Questions []string
	Scenario  string
}

// 使用千问文本模型处理描述，生成多维度搜索内容
func processWithQwenText(description, folderTree string, userFolderID int) (SearchContent, error) {
	if config.QwenTextAPIKey == "" {
		// 模拟响应
		name := "模拟文件标题" + fmt.Sprintf("_%d", len(description)%100)
		digest := "Mock digest: " + description[:min(50, len(description))]
		folderID := userFolderID
		if folderID == 0 {
			folderID = 0 // 默认根文件夹
		}
		return SearchContent{
			Name:      name,
			Digest:    digest,
			FolderID:  folderID,
			Keywords:  "模拟,关键词,测试",
			Questions: []string{"这是什么?", "在哪里找到的?"},
			Scenario:  "模拟场景描述",
		}, nil
	}

	prompt := fmt.Sprintf(`
根据以下图片描述和文件夹结构，请：
1. 生成一个简洁的文件标题（不超过20字，适合作为文件名）
2. 生成一个简洁的摘要（不超过100字）
3. 推荐最合适的存储文件夹ID
4. 生成用户可能搜索的关键词（5-10个，用逗号分隔）
5. 生成用户可能提出的问题（2-3个）
6. 生成场景描述（简短描述这是什么场景/情况）

图片描述：
%s

文件夹结构：
%s

用户指定的文件夹ID：%d（如果为0表示未指定）

请以JSON格式回复：
{
  "name": "文件标题",
  "digest": "摘要内容",
  "folder_id": 推荐的文件夹ID,
  "keywords": "关键词1,关键词2,关键词3",
  "questions": ["用户可能的问题1", "用户可能的问题2"],
  "scenario": "场景描述"
}
`, description, folderTree, userFolderID)

	requestBody := map[string]interface{}{
		"model": "qwen-turbo",
		"input": map[string]interface{}{
			"messages": []map[string]interface{}{
				{
					"role":    "user",
					"content": prompt,
				},
			},
		},
	}

	jsonData, err := json.Marshal(requestBody)
	if err != nil {
		return SearchContent{}, err
	}

	req, err := http.NewRequest("POST", "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation", bytes.NewBuffer(jsonData))
	if err != nil {
		return SearchContent{}, err
	}

	req.Header.Set("Authorization", "Bearer "+config.QwenTextAPIKey)
	req.Header.Set("Content-Type", "application/json")

	fmt.Printf("Calling Qwen Text API with key: %s...\n", config.QwenTextAPIKey[:10])

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("HTTP Request error: %v\n", err)
		return SearchContent{}, err
	}
	defer resp.Body.Close()

	fmt.Printf("Text API Response Status: %s\n", resp.Status)

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		fmt.Printf("Response body read error: %v\n", err)
		return SearchContent{}, err
	}

	fmt.Printf("Text API Response Body: %s\n", string(body))

	var response QwenTextResponse
	if err := json.Unmarshal(body, &response); err != nil {
		fmt.Printf("JSON Unmarshal error: %v\n", err)
		return SearchContent{}, err
	}

	if response.Output.Text == "" {
		fmt.Printf("No text in response: %+v\n", response)
		return SearchContent{}, fmt.Errorf("no response from Qwen text model")
	}

	// 解析JSON响应
	var result struct {
		Name      string   `json:"name"`
		Digest    string   `json:"digest"`
		FolderID  int      `json:"folder_id"`
		Keywords  string   `json:"keywords"`
		Questions []string `json:"questions"`
		Scenario  string   `json:"scenario"`
	}

	content := response.Output.Text
	if err := json.Unmarshal([]byte(content), &result); err != nil {
		// 如果解析失败，使用默认值
		result.Name = "未命名文件"
		result.Digest = content[:min(100, len(content))]
		result.FolderID = userFolderID
		if result.FolderID == 0 {
			result.FolderID = 0
		}
		result.Keywords = "默认关键词"
		result.Questions = []string{"这是什么?"}
		result.Scenario = "未知场景"
	}

	return SearchContent{
		Name:      result.Name,
		Digest:    result.Digest,
		FolderID:  result.FolderID,
		Keywords:  result.Keywords,
		Questions: result.Questions,
		Scenario:  result.Scenario,
	}, nil
}

// 创建对象
func createObject(name, imageData, description string, folderID int) (int, error) {
	result, err := db.Exec("INSERT INTO objects (name, data, description, folder_id) VALUES (?, ?, ?, ?)",
		name, imageData, description, folderID)
	if err != nil {
		return 0, err
	}

	id, err := result.LastInsertId()
	if err != nil {
		return 0, err
	}

	return int(id), nil
}

// 存储到向量数据库（多维度内容）
func storeInVectorDB(objectID int, searchContent SearchContent) error {
	ctx := context.Background()
	
	// 构建综合搜索内容，包含所有维度
	combinedContent := fmt.Sprintf("%s\n关键词: %s\n场景: %s", 
		searchContent.Digest, 
		searchContent.Keywords, 
		searchContent.Scenario)
	
	// 添加问题内容
	for _, question := range searchContent.Questions {
		combinedContent += "\n问题: " + question
	}
	
	// 主文档：综合内容
	mainDoc := chromem.Document{
		ID:      strconv.Itoa(objectID),
		Content: combinedContent,
	}
	
	if err := collection.AddDocument(ctx, mainDoc); err != nil {
		return err
	}
	
	// 额外存储：关键词文档（提高关键词匹配权重）
	keywordDoc := chromem.Document{
		ID:      strconv.Itoa(objectID) + "_keywords",
		Content: searchContent.Keywords,
		Metadata: map[string]string{
			"type":      "keywords",
			"object_id": strconv.Itoa(objectID),
		},
	}
	
	if err := collection.AddDocument(ctx, keywordDoc); err != nil {
		return err
	}
	
	// 额外存储：问题文档（提高问题匹配权重）
	for i, question := range searchContent.Questions {
		questionDoc := chromem.Document{
			ID:      fmt.Sprintf("%d_question_%d", objectID, i),
			Content: question,
			Metadata: map[string]string{
				"type":      "question",
				"object_id": strconv.Itoa(objectID),
			},
		}
		
		if err := collection.AddDocument(ctx, questionDoc); err != nil {
			return err
		}
	}
	
	return nil
}

// 根据ID获取对象
func getObjectByID(id int) (Object, error) {
	var obj Object
	err := db.QueryRow("SELECT id, name, data, description, folder_id FROM objects WHERE id = ?", id).Scan(
		&obj.ID, &obj.Name, &obj.Data, &obj.Description, &obj.FolderID)
	return obj, err
}

// 创建文件夹
func createFolder(name string, upper int) (int, error) {
	// 检查同一父文件夹下是否已存在同名文件夹
	var count int
	err := db.QueryRow("SELECT COUNT(*) FROM folders WHERE name = ? AND upper = ?", name, upper).Scan(&count)
	if err != nil {
		return 0, err
	}

	if count > 0 {
		return 0, fmt.Errorf("文件夹 '%s' 在当前位置已存在", name)
	}

	result, err := db.Exec("INSERT INTO folders (name, upper) VALUES (?, ?)", name, upper)
	if err != nil {
		return 0, err
	}

	id, err := result.LastInsertId()
	if err != nil {
		return 0, err
	}

	return int(id), nil
}

// 更新文件夹
func updateFolder(id int, name string, upper int) error {
	_, err := db.Exec("UPDATE folders SET name = ?, upper = ? WHERE id = ?", name, upper, id)
	return err
}

// 删除文件夹
func deleteFolder(id int) error {
	// 检查是否为根文件夹
	if id == 0 {
		return fmt.Errorf("不能删除根文件夹")
	}

	// 检查文件夹是否存在
	var count int
	err := db.QueryRow("SELECT COUNT(*) FROM folders WHERE id = ?", id).Scan(&count)
	if err != nil {
		return err
	}
	if count == 0 {
		return fmt.Errorf("文件夹不存在")
	}

	// 检查是否有子文件夹
	err = db.QueryRow("SELECT COUNT(*) FROM folders WHERE upper = ?", id).Scan(&count)
	if err != nil {
		return err
	}
	if count > 0 {
		return fmt.Errorf("文件夹不为空，请先删除子文件夹")
	}

	// 检查是否有对象
	err = db.QueryRow("SELECT COUNT(*) FROM objects WHERE folder_id = ?", id).Scan(&count)
	if err != nil {
		return err
	}
	if count > 0 {
		return fmt.Errorf("文件夹不为空，请先删除文件夹中的图片")
	}

	// 删除文件夹
	_, err = db.Exec("DELETE FROM folders WHERE id = ?", id)
	return err
}

// 获取子文件夹
func getSubFolders(parentID int) ([]Folder, error) {
	// 查询子文件夹，排除父文件夹本身
	rows, err := db.Query("SELECT id, name, upper FROM folders WHERE upper = ? AND id != ?", parentID, parentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var folders []Folder
	for rows.Next() {
		var folder Folder
		if err := rows.Scan(&folder.ID, &folder.Name, &folder.Upper); err != nil {
			continue
		}
		folders = append(folders, folder)
	}

	return folders, nil
}

// 获取文件夹中的对象
func getObjectsInFolder(folderID int) ([]Object, error) {
	rows, err := db.Query("SELECT id, name, data, description, folder_id FROM objects WHERE folder_id = ?", folderID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var objects []Object
	for rows.Next() {
		var obj Object
		if err := rows.Scan(&obj.ID, &obj.Name, &obj.Data, &obj.Description, &obj.FolderID); err != nil {
			continue
		}
		objects = append(objects, obj)
	}

	return objects, nil
}

// 辅助函数
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
