# Simple Hello World Python App

A minimal Flask application demonstrating deployment to Azure App Service.

## 🚀 Quick Start

### Local Development

1. **Create a virtual environment:**
   ```bash
   python -m venv venv
   ```

2. **Activate the virtual environment:**
   - Windows PowerShell:
     ```powershell
     .\venv\Scripts\Activate.ps1
     ```
   - Linux/Mac:
     ```bash
     source venv/bin/activate
     ```

3. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

4. **Run the application:**
   ```bash
   python app.py
   ```

5. **Open your browser:**
   Navigate to `http://localhost:5000`

## 📦 Project Structure

```
sample-app/
├── app.py              # Main Flask application
├── requirements.txt    # Python dependencies
├── .gitignore         # Git ignore rules
└── README.md          # This file
```

## 🌐 API Endpoints

- `/` - Home page with Hello World message
- `/health` - Health check endpoint
- `/api/info` - JSON endpoint with application information

## 🔧 Technologies

- **Python**: 3.11+
- **Flask**: 3.0.0
- **Gunicorn**: 21.2.0 (WSGI server for production)

## 📝 Deployment to Azure

This application is designed to be deployed to Azure App Service. See the parent directory's README for deployment instructions.

### Quick Deploy with Azure CLI

```bash
az webapp up --name <your-app-name> --resource-group <your-resource-group> --runtime "PYTHON:3.11"
```

## 🧪 Testing

The application includes a health check endpoint for monitoring:

```bash
curl http://localhost:5000/health
```

Response:
```json
{
  "status": "healthy",
  "timestamp": "2025-10-10T12:00:00",
  "service": "simple-app-service-python"
}
```

## 📄 License

This project is part of the Azure Scenario Hub.
