"""
Simple Hello World Flask Application
This is a basic Python web application for Azure App Service demonstration.
"""

from flask import Flask, render_template_string
import os
from datetime import datetime

app = Flask(__name__)

# HTML template for the home page
HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Hello World - Azure App Service</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 20px;
            padding: 40px;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
            max-width: 600px;
            width: 100%;
            text-align: center;
        }
        h1 {
            color: #333;
            margin-bottom: 20px;
            font-size: 2.5em;
        }
        .emoji {
            font-size: 4em;
            margin: 20px 0;
        }
        .info {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 20px;
            margin: 20px 0;
            text-align: left;
        }
        .info-item {
            margin: 10px 0;
            padding: 10px;
            background: white;
            border-radius: 5px;
            border-left: 4px solid #667eea;
        }
        .label {
            font-weight: bold;
            color: #667eea;
        }
        .footer {
            margin-top: 30px;
            color: #666;
            font-size: 0.9em;
        }
        a {
            color: #667eea;
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="emoji">👋</div>
        <h1>Hello, World!</h1>
        <p style="font-size: 1.2em; color: #666; margin-bottom: 20px;">
            Welcome to your Python Flask app running on Azure App Service
        </p>
        
        <div class="info">
            <div class="info-item">
                <span class="label">Python Version:</span> {{ python_version }}
            </div>
            <div class="info-item">
                <span class="label">Flask Version:</span> {{ flask_version }}
            </div>
            <div class="info-item">
                <span class="label">Server Time:</span> {{ current_time }}
            </div>
            <div class="info-item">
                <span class="label">Hostname:</span> {{ hostname }}
            </div>
        </div>

        <div class="footer">
            <p>Built with ❤️ for Azure Scenario Hub</p>
            <p style="margin-top: 10px;">
                <a href="/health">Health Check</a> | 
                <a href="https://github.com/Ricky-G/azure-scenario-hub" target="_blank">GitHub</a>
            </p>
        </div>
    </div>
</body>
</html>
"""

@app.route('/')
def home():
    """Home page route"""
    import sys
    import flask
    
    return render_template_string(
        HTML_TEMPLATE,
        python_version=sys.version.split()[0],
        flask_version=flask.__version__,
        current_time=datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC'),
        hostname=os.getenv('WEBSITE_HOSTNAME', 'localhost')
    )

@app.route('/health')
def health():
    """Health check endpoint"""
    return {
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'service': 'simple-app-service-python'
    }, 200

@app.route('/api/info')
def info():
    """API endpoint returning application information"""
    import sys
    import flask
    
    return {
        'application': 'Hello World Python App',
        'version': '1.0.0',
        'python_version': sys.version,
        'flask_version': flask.__version__,
        'environment': os.getenv('ENVIRONMENT', 'development'),
        'hostname': os.getenv('WEBSITE_HOSTNAME', 'localhost'),
        'timestamp': datetime.now().isoformat()
    }, 200

if __name__ == '__main__':
    # For local development
    port = int(os.getenv('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=True)
