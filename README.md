# Apache Guacamole Docker Compose Setup

This repository contains a complete Docker Compose setup for Apache Guacamole, a clientless remote desktop gateway that supports standard protocols like VNC, RDP, and SSH.

## Architecture

The setup includes:

- **PostgreSQL Database**: Stores Guacamole configuration and user data
- **Guacd Server**: Handles the actual remote desktop connections
- **Guacamole Web Application**: Provides the web interface
- **Nginx Reverse Proxy** (Optional): Handles SSL termination and load balancing

## Quick Start

1. **Clone and navigate to the directory:**

   ```bash
   cd /Users/vishal/Projects/Guacamole
   ```

2. **Configure environment variables:**

   ```bash
   cp .env.example .env
   # Edit .env file with your preferred settings
   ```

3. **Start the services:**

   ```bash
   docker-compose up -d
   ```

4. **Access Guacamole:**
   - Open your browser and go to `http://localhost:8080`
   - Default credentials: `guacadmin` / `guacadmin`

## Configuration

### Environment Variables

Edit the `.env` file to customize your setup:

```bash
# Guacamole Configuration
GUACAMOLE_PORT=8080
GUACD_LOG_LEVEL=info

# Database Configuration
POSTGRES_DB=guacamole_db
POSTGRES_USER=guacamole_user
POSTGRES_PASSWORD=guacamole_password

# Nginx Configuration (Optional)
NGINX_HTTP_PORT=80
NGINX_HTTPS_PORT=443
```

### Security Considerations

⚠️ **Important**: Change the default passwords before deploying to production!

1. Update the database password in `.env`
2. Change the default Guacamole admin password after first login
3. Consider enabling SSL/TLS with proper certificates

## Services

### Core Services

- **guacamole**: Web application (port 8080)
- **guacd**: Guacamole daemon (internal)
- **postgres**: PostgreSQL database (internal)

### Optional Services

- **nginx**: Reverse proxy with SSL support (ports 80/443)

To start with Nginx:

```bash
docker-compose --profile nginx up -d
```

## Directory Structure

```
.
├── docker-compose.yml          # Main Docker Compose configuration
├── .env                        # Environment variables
├── init/
│   └── init-db.sql            # Database initialization script
├── nginx/
│   ├── nginx.conf             # Nginx configuration
│   └── ssl/                   # SSL certificates (create as needed)
├── extensions/                # Guacamole extensions
├── lib/                       # Additional libraries
├── drive/                     # File transfer directory
├── record/                    # Session recordings
└── guacamole-properties/
    └── guacamole.properties   # Guacamole configuration
```

## Usage

### Basic Operations

**Start services:**

```bash
docker-compose up -d
```

**Stop services:**

```bash
docker-compose down
```

**View logs:**

```bash
docker-compose logs -f guacamole
```

**Restart a service:**

```bash
docker-compose restart guacamole
```

### Adding Connections

1. Log in to the web interface
2. Go to Settings → Connections
3. Click "New Connection"
4. Configure your connection:
   - **Name**: Display name for the connection
   - **Protocol**: RDP, VNC, SSH, or Telnet
   - **Hostname**: Target server IP/hostname
   - **Port**: Target port (defaults provided)
   - **Username/Password**: Credentials for the target

### File Transfer

- Files can be uploaded/downloaded through the web interface
- Files are stored in the `./drive` directory
- Enable/disable in `guacamole-properties/guacamole.properties`

### Session Recording

- Sessions can be recorded for audit purposes
- Recordings are stored in the `./record` directory
- Enable/disable in `guacamole-properties/guacamole.properties`

## Troubleshooting

### Common Issues

1. **Database connection errors:**

   ```bash
   docker-compose logs postgres
   ```

2. **Guacd connection issues:**

   ```bash
   docker-compose logs guacd
   ```

3. **Web interface not loading:**
   ```bash
   docker-compose logs guacamole
   ```

### Health Checks

All services include health checks. Check status:

```bash
docker-compose ps
```

### Reset Everything

To start fresh (⚠️ **This will delete all data**):

```bash
docker-compose down -v
docker-compose up -d
```

## Advanced Configuration

### SSL/TLS Setup

1. Place your SSL certificates in `nginx/ssl/`
2. Update `nginx/nginx.conf` to uncomment the HTTPS server block
3. Start with nginx profile: `docker-compose --profile nginx up -d`

### Custom Extensions

Place `.jar` files in the `extensions/` directory to add custom functionality.

### Performance Tuning

Adjust settings in `guacamole-properties/guacamole.properties`:

- `max-connections`: Maximum concurrent connections
- `max-connections-per-user`: Per-user connection limit
- `session-timeout`: Session timeout in seconds

## Support

- [Apache Guacamole Documentation](https://guacamole.apache.org/doc/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

## License

This setup is provided as-is for educational and development purposes. Please review and comply with the licenses of all included software components.
