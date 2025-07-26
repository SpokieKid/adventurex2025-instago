package main

import (
	"fmt"
	"github.com/spf13/viper"
)

func initConfig() {
	viper.SetConfigName("config")
	viper.SetConfigType("yaml")
	viper.AddConfigPath(".")

	if err := viper.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); ok {
			fmt.Println("配置文件未找到，使用默认值")
		} else {
			panic(fmt.Errorf("读取配置文件错误: %w", err))
		}
	}
}
