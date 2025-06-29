# 🪔 Interactive Lamp Web App

A beautiful, interactive hanging lamp web application built with FastAPI and modern web technologies.

## ✨ Features

- **Interactive Lamp**: Pull the string to toggle the lamp on/off
- **Beautiful Animations**: Smooth transitions and realistic lighting effects
- **Responsive Design**: Works perfectly on desktop, tablet, and mobile
- **Modern UI**: Clean, minimalist design with dark theme
- **Docker Ready**: Production-ready containerization
- **Accessibility**: Full keyboard navigation and screen reader support

## 🏗️ Project Structure

```
lamp_web_app/
├── src/                    # Source code directory
│   ├── main.py            # FastAPI application entry point
│   ├── server.py          # Server configuration (if needed)
│   ├── static/            # Static assets
│   │   ├── style.css      # Application styles
│   │   └── script.js      # JavaScript functionality
│   └── templates/         # Jinja2 templates
│       └── index.html     # Main application template
├── Dockerfile             # Docker container definition
├── docker-compose.yml     # Development Docker Compose
├── docker-compose.prod.yml # Production Docker Compose
├── .dockerignore          # Docker ignore file
├── requirements.txt       # Python dependencies
├── start.sh              # Development start script
└── README.md             # This file
```

## 🚀 Quick Start

### Option 1: Docker (Recommended)

1. **Build and run with Docker Compose:**
   ```bash
   docker-compose up --build
   ```

2. **For production:**
   ```bash
   docker-compose -f docker-compose.prod.yml up --build -d
   ```

3. **Access the application:**
   Open http://localhost:8000 in your browser

### Option 2: Local Development

1. **Install dependencies:**
   ```bash
   chmod +x start.sh
   ./start.sh
   ```

2. **Or manually:**
   ```bash
   python3 -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   pip install -r requirements.txt
   python src/main.py
   ```

## 🐳 Docker Commands

### Development
```bash
# Build the image
docker build -t lamp-app .

# Run the container
docker run -p 8000:8000 lamp-app

# Run with environment variables
docker run -p 8000:8000 -e PORT=8000 lamp-app
```

### Production
```bash
# Build for production
docker build -t lamp-app:prod .

# Run in production mode
docker run -d --name lamp-app -p 8000:8000 --restart unless-stopped lamp-app:prod
```

## 🛠️ Docker Best Practices Implemented

- **Multi-stage builds**: Optimized image size
- **Non-root user**: Enhanced security
- **Health checks**: Container health monitoring
- **Environment variables**: Configurable runtime
- **Slim base image**: Python 3.13-slim for smaller footprint
- **Layer caching**: Efficient builds with proper layer ordering
- **Security**: No new privileges, resource limits

## 🔧 Configuration

### Environment Variables

- `PORT`: Application port (default: 8000)
- `PYTHONPATH`: Python path (set to `/app/src` in Docker)

### Health Check

The application includes a health check endpoint at `/health`

## 🎨 Technologies Used

- **Backend**: FastAPI (Python 3.13)
- **Frontend**: Vanilla JavaScript, CSS3, HTML5
- **Animations**: Anime.js library
- **Containerization**: Docker & Docker Compose
- **Web Server**: Uvicorn (ASGI server)

## 📱 Browser Support

- Chrome 90+
- Firefox 88+
- Safari 14+
- Edge 90+

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with Docker
5. Submit a pull request

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

## 🔗 API Endpoints

- `GET /`: Main application interface
- `GET /health`: Health check endpoint
- `GET /static/*`: Static file serving
