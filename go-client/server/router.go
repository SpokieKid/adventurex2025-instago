package main

import "github.com/gin-gonic/gin"

func initRouter(server *gin.Engine) *gin.Engine {
	server.GET("/", func(c *gin.Context) {})
	return server
}
