package main

import (
	"github.com/gin-gonic/gin"
	"github.com/spf13/viper"
)

func main() {
	initConfig()

	s := gin.Default()
	s.Handle("GET", "/ping", func(c *gin.Context) { c.JSON(200, gin.H{"message": "pong"}) })
	_ = s.Run(":" + viper.GetString("RemotePort"))
}
