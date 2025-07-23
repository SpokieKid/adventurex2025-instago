package main

import (
	"encoding/json"
	"log"
	"net/http"
)

func main() {
	// 监听http9090端口，get方法，ping路由，返回json格式，key：message，value：pong
	http.HandleFunc("/ping", func(w http.ResponseWriter, r *http.Request) {
		// 设置响应头为JSON格式
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"message": "pong"})
	})

	log.Println("服务器启动，监听 :9090 端口...")
	log.Fatal(http.ListenAndServe(":9090", nil))
}
