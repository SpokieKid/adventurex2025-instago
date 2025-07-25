#!/usr/bin/env python3
"""
InstaGo 测试服务器
用于接收和处理从 InstaGo 应用上传的图片

启动方法：
python3 test-server.py

服务器将在 http://localhost:3000 运行
"""

from flask import Flask, request, jsonify
import os
from datetime import datetime

app = Flask(__name__)

# 创建上传目录
UPLOAD_FOLDER = 'uploads'
if not os.path.exists(UPLOAD_FOLDER):
    os.makedirs(UPLOAD_FOLDER)

@app.route('/upload', methods=['POST'])
def upload_image():
    try:
        # 检查是否有文件上传
        if 'image' not in request.files:
            return jsonify({'error': 'No image file provided'}), 400
        
        file = request.files['image']
        if file.filename == '':
            return jsonify({'error': 'No file selected'}), 400
        
        # 获取文字标签
        label = request.form.get('label', '')
        
        # 生成唯一文件名
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        # 如果有标签，在文件名中包含标签信息
        if label:
            # 清理标签中的特殊字符，用于文件名
            clean_label = "".join(c for c in label if c.isalnum() or c in (' ', '-', '_')).rstrip()
            clean_label = clean_label.replace(' ', '_')
            filename = f"image_{timestamp}_{clean_label}.jpg"
        else:
            filename = f"image_{timestamp}.jpg"
        
        filepath = os.path.join(UPLOAD_FOLDER, filename)
        
        # 保存文件
        file.save(filepath)
        
        print(f"✅ 接收到图片: {filename}")
        print(f"📁 保存路径: {filepath}")
        print(f"📊 文件大小: {os.path.getsize(filepath)} bytes")
        if label:
            print(f"🏷️  图片标签: {label}")
        
        # 这里可以添加您的图片处理逻辑
        # 例如：OCR、图像识别、格式转换等
        # 现在可以结合标签进行更精准的处理
        
        response_data = {
            'success': True,
            'message': '图片上传成功',
            'filename': filename,
            'size': os.path.getsize(filepath),
            'label': label
        }
        
        return jsonify(response_data), 200
        
    except Exception as e:
        print(f"❌ 上传错误: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'ok', 'message': 'InstaGo 测试服务器运行中'}), 200

@app.route('/', methods=['GET'])
def index():
    return """
    <h1>InstaGo 测试服务器</h1>
    <p>服务器正在运行，等待接收图片上传...</p>
    <p>上传端点: <code>POST /upload</code></p>
    <p>健康检查: <code>GET /health</code></p>
    """

if __name__ == '__main__':
    print("🚀 启动 InstaGo 测试服务器...")
    print("📡 访问地址: http://localhost:3000")
    print("📁 上传目录: ./uploads/")
    print("💡 使用 Ctrl+C 停止服务器")
    
    app.run(host='0.0.0.0', port=3000, debug=True) 