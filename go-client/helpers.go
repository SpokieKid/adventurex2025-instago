package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	chromem "github.com/philippgille/chromem-go"
)

// 千问视觉模型分析图片
func analyzeImageWithQwenVL(image UploadRequest) (string, error) {
	if config.QwenVLAPIKey == "" {
		return "Mock description: This is a sample image description for testing purposes.", nil
	}

	// 构建请求体 - 修复千问VL API格式
	prompt := "您擅长分析截图内容并基于其内容自动化任务，最终向用户输出有用的信息。\n"

	if image.ScreenshotTimestamp > 0 {
		// 将毫秒时间戳转换为小时精度
		timestampInHours := (image.ScreenshotTimestamp / 3600000) * 3600000
		prompt += fmt.Sprintf("截图时间戳(单位：毫秒): %d\n", timestampInHours)
	}
	if image.ScreenshotAppName != "" {
		prompt += fmt.Sprintf("来源应用: %s\n", image.ScreenshotAppName)
	}
	if image.ScreenshotTags != "" {
		prompt += fmt.Sprintf("标签: %s\n", image.ScreenshotTags)
	}
	prompt += "请详细描述这张截图的内容，包括文本、界面元素、操作步骤等所有可见信息。\n" +
		"你应该优先设置描述的属性：截图时间戳、来源应用、标签 \n" +
		"你应该在描述的最后一部分给出一段具有特定标识的原文内容（约15-20字），并分析这份图片可能来自哪个站点。输出格式：'可能来自的站点':'推特、微博、小红书','原文内容':'15-20字的能够找到原文的原文内容。'\n"
	requestBody := map[string]interface{}{
		"model": "qwen-vl-plus",
		"input": map[string]interface{}{
			"messages": []map[string]interface{}{
				{
					"role": "user",
					"content": []map[string]interface{}{
						{
							"image": fmt.Sprintf("data:image/jpeg;base64,%s", image.ScreenshotFileBlob),
						},
						{
							"text": prompt,
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
	Name          string
	Digest        string
	FolderID      int
	Keywords      string
	Questions     []string
	Scenario      string
	FromSite      string
	OriginContent string
}

// 使用千问文本模型处理描述，生成多维度搜索内容
func processWithQwenText(description, folderTree string) (SearchContent, error) {
	if config.QwenTextAPIKey == "" {
		return SearchContent{}, errors.New("QwenText API key is not set")
	}

	prompt := fmt.Sprintf(`
根据以下图片描述和文件夹结构，请：
1. 生成一个简洁的文件标题（不超过20字，适合作为文件名）
2. 生成一个简洁的摘要(大约在150字，需要包含图片描述的关键属性比如精确到小时的毫秒级时间戳、来源应用、标签）
3. 推荐最合适的存储文件夹ID：注意：你应该详细分析文件夹结构，比如一个父级文件夹可能指向“品牌”，“类别”，子文件夹是更具体的信息，一个可能的场景比如：
 "算法\n\t力扣\n\t洛谷"，这个说明在算法文件夹下存在着力扣、洛谷两个子文件夹，如果一个截图内容中包含“力扣”、“leetcode”字样，你应该将其放在力扣文件夹下。
4. 生成用户可能搜索的关键词（5-10个，用逗号分隔，需要有精确到小时的毫秒级时间戳）
5. 生成用户可能会为了找到这张图片描述的语义化信息（3-4个)。
6. 生成场景描述（简短描述这是什么场景/情况）。
7. 图片描述的最后部分是可能在搜索引擎上找到原文的内容，类似于：'可能来自的站点':'推特、微博、小红书','原文内容':'15-20字的能够找到原文的原文内容。'，请不要
修改这两个字段，填充在响应中。
注意，请关注图片描述的重点属性，比如时间，用户可能会问我在昨天下午or我在某月某日截取的图片在哪，为了匹配性，你应该将时间戳截取成每半个小时作为一个单位（后位填充0），作为关键词之一。

图片描述：
%s

文件夹结构：
%s

请以JSON格式回复：
{
  "name": "文件标题",
  "digest": "摘要内容",
  "folder_id": 推荐的文件夹ID,
  "keywords": "关键词1,关键词2,关键词3",
  "questions": ["用户可能会为了找到这张图片描述的语义化信息1", "用户可能会为了找到这张图片描述的语义化信息2","用户可能会为了找到这张图片描述的语义化信息3"],
  "scenario": "场景描述",
  "from_site":"可能来自的站点",
  "origin_content":"原文内容"
}
`, description, folderTree)

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

	// 解析JSON响应 - 处理folder_id可能为字符串的情况
	var result struct {
		Name          string      `json:"name"`
		Digest        string      `json:"digest"`
		FolderID      interface{} `json:"folder_id"`
		Keywords      string      `json:"keywords"`
		Questions     []string    `json:"questions"`
		Scenario      string      `json:"scenario"`
		FromSite      string      `json:"from_site"`
		OriginContent string      `json:"origin_content"` // 很少的一部分文本
	}

	content := response.Output.Text
	if err = json.Unmarshal([]byte(content), &result); err != nil {
		// 如果解析失败，使用默认值
		return SearchContent{}, err
	}

	// 处理folder_id类型转换
	var folderID int
	switch v := result.FolderID.(type) {
	case float64:
		folderID = int(v)
	case string:
		if parsed, parseErr := strconv.Atoi(v); parseErr == nil {
			folderID = parsed
		} else {
			folderID = 0 // 默认根文件夹
		}
	case int:
		folderID = v
	default:
		folderID = 0 // 默认根文件夹
	}

	return SearchContent{
		Name:          result.Name,
		Digest:        result.Digest,
		FolderID:      folderID,
		Keywords:      result.Keywords,
		Questions:     result.Questions,
		Scenario:      result.Scenario,
		FromSite:      result.FromSite,
		OriginContent: result.OriginContent,
	}, nil
}

func standardizeQueryWithOllama(userQuery string) (string, error) {
	// todo: 太他妈傻逼了
	//// 获取当前时间信息
	//currentTime := time.Now().Truncate(time.Hour)
	//
	//currentTimestamp := currentTime.UnixMilli()
	//currentDate := currentTime.Format("2006年01月02日 15:04")
	//weekday := currentTime.Weekday()
	//weekdayMap := map[time.Weekday]string{
	//	time.Sunday: "周日", time.Monday: "周一", time.Tuesday: "周二",
	//	time.Wednesday: "周三", time.Thursday: "周四", time.Friday: "周五", time.Saturday: "周六",
	//}
	//yesterdayTime14oclock := currentTime.AddDate(0, 0, -1).Truncate(24 * time.Hour).Add(14 * time.Hour).UnixMilli()
	//daybeforeyestday := currentTime.AddDate(0, 0, -2).UnixMilli()
	//	prompt := fmt.Sprintf(`你是一个查询标准化助手。用户会输入搜索查询，你需要：
	//
	//1. 如果查询中包含时间概念（如"昨天"、"三天前"、"上周"、"今天下午"等），请计算出对应的精确到小时的毫秒级时间戳，小时后面的位全部置0
	//2. 保留原始查询的核心内容
	//3. 返回标准化后的查询语句
	//
	//当前时间信息：
	//- 当前时间：%s (%s)
	//- 当前时间戳（毫秒）：%d
	//- 时间戳计算方式：将目标时间精确到小时，即分钟和秒都设为0，然后转换为毫秒时间戳
	//
	//示例：
	//- 用户查询："昨天下午的截图"
	//- 标准化查询："昨天下午的截图 时间戳:%d"（假设昨天下午2点对应的毫秒时间戳）
	//
	//- 用户查询："三天前看到的代码"
	//- 标准化查询："三天前看到的代码 时间戳:%d"（假设三天前对应的毫秒时间戳）
	//
	//用户查询："%s"
	//
	//请返回标准化后的查询语句：`, currentDate, weekdayMap[weekday], currentTimestamp, yesterdayTime14oclock, daybeforeyestday, userQuery)
	prompt := fmt.Sprintf(`注意：不要参考历史上下文。\n
你是一个查询标准化助手。用户会输入搜索查询，你需要返回标准化后的查询语句，\n

注意：\n
1. 你不能解释某个关键的词语，因为我需要根据关键词进行搜索。\n
2. 语句本身没有对话的含义，你只需要去除其中的不重要的信息。\n
3. 尝试多个维度去描述这个查询。\n
用户描述的内容是："%s"\n

请返回你标准化处理后的查询语句，不要携带其他内容，只返回json，按照此格式返回：\n
{
	"response": ""
}\n
参考示例：\n
用户查询：我做的一个链表的题。\n
返回：{
	"response": "链表，算法题"
}\n
用户查询：一篇有关中医、医药的文章。\n
返回：{
	"response": "中医、医药、文章"
}\n
`, userQuery)

	requestBody := map[string]interface{}{
		"model":  "qwen2:0.5b",
		"prompt": prompt,
		"stream": false,
	}
	jsonData, err := json.Marshal(requestBody)
	if err != nil {
		return userQuery, err // 如果出错，返回原查询
	}
	req, err := http.NewRequest("POST", "http://localhost:11434/api/generate", bytes.NewBuffer(jsonData))
	if err != nil {
		return userQuery, err
	}
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("Ollama请求失败，使用原查询: %v\n", err)
		return userQuery, nil // 如果Ollama不可用，返回原查询
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return userQuery, err
	}

	var response struct {
		Response string `json:"response"`
	}

	if err := json.Unmarshal(body, &response); err != nil {
		return userQuery, err
	}

	standardizedQuery := strings.TrimSpace(response.Response)
	if standardizedQuery == "" {
		return userQuery, nil
	}

	fmt.Printf("查询标准化: '%s' -> '%s'\n", userQuery, standardizedQuery)
	return standardizedQuery, nil

}

// 创建对象
func createObject(name, imageData, description string, folderID int, possibleFrom string) (int, error) {
	result, err := db.Exec("INSERT INTO objects (name, data, description, folder_id,possible_from) VALUES (?, ?, ?, ?,?)",
		name, imageData, description, folderID, possibleFrom)
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
	err := db.QueryRow("SELECT id, name, data, description, folder_id,possible_from FROM objects WHERE id = ?", id).Scan(
		&obj.ID, &obj.Name, &obj.Data, &obj.Description, &obj.FolderID, &obj.PossibleFrom)
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
	rows, err := db.Query("SELECT id, name, data, description, folder_id,possible_from FROM objects WHERE folder_id = ?", folderID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var objects []Object
	for rows.Next() {
		var obj Object
		if err := rows.Scan(&obj.ID, &obj.Name, &obj.Data, &obj.Description, &obj.FolderID, &obj.PossibleFrom); err != nil {
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
