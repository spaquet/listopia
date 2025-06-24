# Installation Guide

This guide covers how to deploy Listopia in production using Kamal (Rails 8's recommended deployment tool).

## Prerequisites

- **Ruby 3.2+** on your local machine
- **Docker** installed locally and on production servers
- **PostgreSQL 17.5+** database
- **SMTP service** for email delivery
- **Domain name** with SSL certificate

## Production Deployment with Kamal

### 1. Server Requirements

**Minimum server specifications:**
- 1GB RAM (2GB+ recommended)
- 1 CPU core
- 20GB disk space
- Ubuntu 20.04+ or similar Linux distribution
- Docker installed

### 2. Database Setup

**Option A: Managed PostgreSQL (Recommended)**
- Use a managed PostgreSQL service (AWS RDS, Digital Ocean, etc.)
- Create a database with PostgreSQL 17.5+
- Enable the `uuid-ossp` and `pgcrypto` extensions

**Option B: Self-hosted PostgreSQL**
```bash
# Install PostgreSQL on your server
sudo apt update
sudo apt install postgresql postgresql-contrib

# Create database and user
sudo -u postgres createdb listopia_production
sudo -u postgres createuser listopia
sudo -u postgres psql -c "ALTER USER listopia WITH PASSWORD 'your_secure_password';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE listopia_production TO listopia;"

# Enable extensions
sudo -u postgres psql -d listopia_production -c "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";"
sudo -u postgres psql -d listopia_production -c "CREATE EXTENSION IF NOT EXISTS \"pgcrypto\";"
```

### 3. Email Configuration

Configure SMTP for production email delivery. Update these settings in your deployment:

**Supported SMTP providers:**
- **Gmail/Google Workspace**
- **SendGrid**
- **Mailgun**
- **Amazon SES**
- **Postmark**

### 4. Kamal Configuration

#### Step 1: Update deploy.yml

Edit `config/deploy.yml`:

```yaml
# Name of your application
service: listopia

# Your Docker Hub username or registry
image: your-dockerhub-username/listopia

# Production servers
servers:
  web:
    - your-server-ip-address

# SSL and domain configuration
proxy:
  ssl: true
  host: your-domain.com  # Replace with your domain

# Docker registry credentials
registry:
  username: your-dockerhub-username
  password:
    - KAMAL_REGISTRY_PASSWORD

# Environment variables
env:
  secret:
    - RAILS_MASTER_KEY
    - LISTOPIA_DATABASE_PASSWORD
    - SMTP_PASSWORD
  clear:
    SOLID_QUEUE_IN_PUMA: true
    RAILS_ENV: production
    
    # Database configuration
    LISTOPIA_DATABASE_HOST: your-db-host
    LISTOPIA_DATABASE_USERNAME: listopia
    LISTOPIA_DATABASE_PORT: 5432
    
    # Email configuration
    SMTP_ADDRESS: smtp.your-provider.com
    SMTP_PORT: 587
    SMTP_USERNAME: your-smtp-username
    SMTP_DOMAIN: your-domain.com
    RAILS_HOST: your-domain.com

# Storage for uploaded files
volumes:
  - "listopia_storage:/rails/storage"

# Asset management
asset_path: /rails/public/assets

# Build configuration
builder:
  arch: amd64
```

#### Step 2: Create Kamal secrets

Create `.kamal/secrets` file:

```bash
# Create the secrets file
mkdir -p .kamal
touch .kamal/secrets
chmod 600 .kamal/secrets
```

Add to `.kamal/secrets`:

```bash
# Docker registry password
KAMAL_REGISTRY_PASSWORD=your-docker-hub-password

# Rails master key (from config/master.key)
RAILS_MASTER_KEY=your-rails-master-key

# Database password
LISTOPIA_DATABASE_PASSWORD=your-secure-database-password

# SMTP password
SMTP_PASSWORD=your-smtp-password
```

#### Step 3: Update Production Configuration

Update `config/environments/production.rb`:

```ruby
# Email configuration
config.action_mailer.delivery_method = :smtp
config.action_mailer.perform_deliveries = true
config.action_mailer.raise_delivery_errors = true

# Set your domain for email links
config.action_mailer.default_url_options = { 
  host: ENV.fetch('RAILS_HOST', 'your-domain.com'),
  protocol: 'https'
}

# Rails URL helpers for sharing features
Rails.application.routes.default_url_options[:host] = ENV.fetch('RAILS_HOST', 'your-domain.com')
Rails.application.routes.default_url_options[:protocol] = 'https'

# SMTP settings
config.action_mailer.smtp_settings = {
  address: ENV.fetch('SMTP_ADDRESS'),
  port: ENV.fetch('SMTP_PORT', 587).to_i,
  domain: ENV.fetch('SMTP_DOMAIN'),
  user_name: ENV.fetch('SMTP_USERNAME'),
  password: ENV.fetch('SMTP_PASSWORD'),
  authentication: 'plain',
  enable_starttls_auto: true
}
```

### 5. Email Template URLs

The application sends emails with links. These URLs are automatically generated using your domain configuration. Make sure to update:

1. **Email verification links** - Uses `RAILS_HOST` environment variable
2. **Magic link authentication** - Uses `RAILS_HOST` environment variable  
3. **Collaboration invitations** - Uses `RAILS_HOST` environment variable
4. **List sharing URLs** - Generated dynamically based on your domain

**Important URLs to verify:**
- Email verification: `https://your-domain.com/verify_email/:token`
- Magic links: `https://your-domain.com/authenticate/:token`
- Collaboration invites: `https://your-domain.com/invitations/accept?token=:token`
- Public lists: `https://your-domain.com/public/:slug`

### 6. Deploy with Kamal

#### Initial setup:

```bash
# Install dependencies
bundle install

# Generate Rails master key if not exists
bundle exec rails secret > config/master.key

# Setup Kamal
bundle exec kamal setup
```

#### Deploy:

```bash
# Build and deploy
bundle exec kamal deploy

# Check deployment status
bundle exec kamal logs

# Check app status
bundle exec kamal app details
```

### 7. Database Migration

After successful deployment, run migrations:

```bash
# Run database migrations
bundle exec kamal app exec "bin/rails db:create db:migrate"

# Optional: Seed database
bundle exec kamal app exec "bin/rails db:seed"
```

### 8. SSL Certificate

Kamal automatically handles SSL certificates via Let's Encrypt. Ensure:

1. Your domain points to your server IP
2. Port 80 and 443 are open
3. No other services are using these ports

### 9. Monitoring and Maintenance

#### Health checks:
```bash
# Check application health
curl https://your-domain.com/up

# Check logs
bundle exec kamal logs --follow

# Check running containers
bundle exec kamal app details
```

#### Updates:
```bash
# Deploy updates
bundle exec kamal deploy

# Rollback if needed
bundle exec kamal rollback
```

## SMTP Provider Configuration Examples

### Gmail/Google Workspace
```bash
SMTP_ADDRESS=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password  # Use App Password, not regular password
SMTP_DOMAIN=gmail.com
```

### SendGrid
```bash
SMTP_ADDRESS=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USERNAME=apikey
SMTP_PASSWORD=your-sendgrid-api-key
SMTP_DOMAIN=your-domain.com
```

### Mailgun
```bash
SMTP_ADDRESS=smtp.mailgun.org
SMTP_PORT=587
SMTP_USERNAME=postmaster@mg.your-domain.com
SMTP_PASSWORD=your-mailgun-password
SMTP_DOMAIN=mg.your-domain.com
```

### Amazon SES
```bash
SMTP_ADDRESS=email-smtp.us-east-1.amazonaws.com
SMTP_PORT=587
SMTP_USERNAME=your-ses-username
SMTP_PASSWORD=your-ses-password
SMTP_DOMAIN=your-domain.com
```

### Postmark
```bash
SMTP_ADDRESS=smtp.postmarkapp.com
SMTP_PORT=587
SMTP_USERNAME=your-postmark-server-api-token
SMTP_PASSWORD=your-postmark-server-api-token
SMTP_DOMAIN=your-domain.com
```

### Resend
```bash
SMTP_ADDRESS=smtp.resend.com
SMTP_PORT=587
SMTP_USERNAME=resend
SMTP_PASSWORD=your-resend-api-key
SMTP_DOMAIN=your-domain.com
```

### Brevo (formerly Sendinblue)
```bash
SMTP_ADDRESS=smtp-relay.brevo.com
SMTP_PORT=587
SMTP_USERNAME=your-brevo-login-email
SMTP_PASSWORD=your-brevo-smtp-key
SMTP_DOMAIN=your-domain.com
```

### Mandrill (MailChimp)
```bash
SMTP_ADDRESS=smtp.mandrillapp.com
SMTP_PORT=587
SMTP_USERNAME=your-mandrill-username
SMTP_PASSWORD=your-mandrill-api-key
SMTP_DOMAIN=your-domain.com
```

### Custom SMTP Server
```bash
SMTP_ADDRESS=mail.your-domain.com
SMTP_PORT=587  # or 465 for SSL, 25 for non-encrypted
SMTP_USERNAME=noreply@your-domain.com
SMTP_PASSWORD=your-email-password
SMTP_DOMAIN=your-domain.com
SMTP_AUTHENTICATION=plain  # or login, cram_md5
SMTP_ENABLE_STARTTLS_AUTO=true  # false for port 465
```

## Email Deliverability Best Practices

### SPF, DKIM, and DMARC Configuration

**SPF (Sender Policy Framework) Record:**
Add to your domain's DNS TXT records:

```dns
# For SendGrid
v=spf1 include:sendgrid.net ~all

# For Mailgun
v=spf1 include:mailgun.org ~all

# For Postmark
v=spf1 include:spf.mtasv.net ~all

# For Amazon SES (replace region)
v=spf1 include:amazonses.com ~all

# For custom server
v=spf1 include:your-mail-server.com ~all

# Multiple providers (combine carefully)
v=spf1 include:sendgrid.net include:mailgun.org ~all
```

**DKIM (DomainKeys Identified Mail):**
Each provider provides DKIM keys to add to your DNS:

```dns
# Example DKIM record (provider-specific)
# Name: selector._domainkey.your-domain.com
# Value: v=DKIM1; k=rsa; p=YOUR_PUBLIC_KEY_FROM_PROVIDER
```

**DMARC (Domain-based Message Authentication):**
Add DMARC policy to DNS:

```dns
# Start with monitoring mode
_dmarc.your-domain.com TXT "v=DMARC1; p=none; rua=mailto:dmarc@your-domain.com; ruf=mailto:dmarc@your-domain.com"

# After testing, enforce policy
_dmarc.your-domain.com TXT "v=DMARC1; p=reject; rua=mailto:dmarc@your-domain.com; ruf=mailto:dmarc@your-domain.com"
```

### Email Reputation Management

1. **Use consistent FROM addresses**
2. **Implement proper unsubscribe mechanisms**
3. **Monitor bounce rates and spam complaints**
4. **Warm up new IP addresses gradually**
5. **Use double opt-in for user registrations**
6. **Implement email verification flows**

### Email Content Best Practices

1. **Use plain text alternatives** for HTML emails
2. **Avoid spam trigger words** in subject lines
3. **Include physical address** in email footers
4. **Keep reasonable send volumes** to avoid rate limiting
5. **Monitor delivery rates** and adjust accordingly

## Advanced Kamal Deployment Configurations

### Multi-Server Setup

For high-traffic applications, you can separate web servers from background job processors:

#### Step 1: Update deploy.yml for Multi-Server

```yaml
# config/deploy.yml
service: listopia

servers:
  web:
    - web1.your-domain.com
    - web2.your-domain.com
  job:
    hosts:
      - job1.your-domain.com
      - job2.your-domain.com
    cmd: bin/jobs  # Custom job runner command

proxy:
  ssl: true
  host: your-domain.com

env:
  secret:
    - RAILS_MASTER_KEY
    - LISTOPIA_DATABASE_PASSWORD
  clear:
    # Disable Solid Queue in Puma for web servers
    SOLID_QUEUE_IN_PUMA: false
    
    # Job server specific configuration
    JOB_CONCURRENCY: 5
    WEB_CONCURRENCY: 3
```

#### Step 2: Create Job Server Script

Create `bin/jobs`:

```bash
#!/bin/bash
# bin/jobs
set -e

# Run Solid Queue as standalone supervisor
exec bundle exec rails solid_queue:start
```

#### Step 3: Deploy Multi-Server

```bash
# Deploy to all servers
bundle exec kamal deploy

# Deploy only web servers
bundle exec kamal deploy --roles web

# Deploy only job servers
bundle exec kamal deploy --roles job

# Check status
bundle exec kamal app details --roles web
bundle exec kamal app details --roles job
```

### Database Accessories (Managed PostgreSQL)

Configure Kamal to work with managed database services:

```yaml
# config/deploy.yml
accessories:
  # Optional: Self-hosted PostgreSQL
  postgres:
    image: postgres:17.5-alpine
    host: db.your-domain.com
    port: "5432:5432"
    env:
      clear:
        POSTGRES_DB: listopia_production
        POSTGRES_USER: listopia
      secret:
        - POSTGRES_PASSWORD
    volumes:
      - postgres_data:/var/lib/postgresql/data
    cmd: >
      postgres
      -c max_connections=200
      -c shared_preload_libraries=pg_stat_statements
      -c log_statement=all

  # Optional: Redis for caching/jobs
  redis:
    image: redis:7.2-alpine
    host: cache.your-domain.com
    port: "6379:6379"
    volumes:
      - redis_data:/data
    cmd: redis-server --appendonly yes --maxmemory 1gb --maxmemory-policy allkeys-lru

# Environment for managed services
env:
  clear:
    # For managed PostgreSQL (AWS RDS, Digital Ocean, etc.)
    LISTOPIA_DATABASE_HOST: your-managed-db-host.com
    LISTOPIA_DATABASE_PORT: 5432
    
    # For managed Redis
    REDIS_URL: redis://your-managed-redis-host.com:6379
```

### Redis Integration for High-Traffic

#### Step 1: Update Gemfile

```ruby
# Add to Gemfile
gem 'redis', '~> 5.0'
gem 'connection_pool'
gem 'sidekiq'  # For background jobs
gem 'sidekiq-web'  # Web UI
```

#### Step 2: Configure Redis in Production

```ruby
# config/environments/production.rb
config.cache_store = :redis_cache_store, {
  url: ENV['REDIS_URL'],
  pool_size: ENV.fetch('RAILS_MAX_THREADS', 5).to_i,
  pool_timeout: 5,
  namespace: 'listopia'
}

# Use Sidekiq for background jobs
config.active_job.queue_adapter = :sidekiq
```

#### Step 3: Sidekiq Configuration

```yaml
# config/sidekiq.yml
:verbose: false
:concurrency: 5
:timeout: 25
:retry: 3

:queues:
  - default
  - mailers
  - low_priority

production:
  :concurrency: 10
```

#### Step 4: Deploy with Redis

```yaml
# config/deploy.yml
accessories:
  redis:
    image: redis:7.2-alpine
    host: cache.your-domain.com
    port: "6379:6379"
    volumes:
      - redis_data:/data
    cmd: redis-server --appendonly yes

env:
  clear:
    REDIS_URL: redis://cache.your-domain.com:6379
    SOLID_QUEUE_IN_PUMA: false  # Use Sidekiq instead
```

### Monitoring and Logging Setup

#### Application Performance Monitoring

```yaml
# config/deploy.yml
env:
  secret:
    - NEW_RELIC_LICENSE_KEY  # or other APM
    - SENTRY_DSN
  clear:
    # Enable detailed logging
    RAILS_LOG_LEVEL: info
    RAILS_LOG_TO_STDOUT: true
    
    # Performance monitoring
    RACK_MINI_PROFILER: false  # Disable in production
```

#### Centralized Logging

```yaml
# config/deploy.yml
logging:
  driver: "fluentd"
  options:
    fluentd-address: "logging.your-domain.com:24224"
    tag: "listopia.{{.Name}}"

# Or use syslog
logging:
  driver: "syslog"
  options:
    syslog-address: "tcp://logs.your-domain.com:514"
    tag: "listopia"
```

#### Health Check Endpoints

```ruby
# config/routes.rb
get "health", to: "rails/health#show"
get "readiness", to: "application#readiness"

# app/controllers/application_controller.rb
def readiness
  # Check database connectivity
  ActiveRecord::Base.connection.execute("SELECT 1")
  
  # Check Redis connectivity (if using)
  Redis.current.ping if defined?(Redis)
  
  render json: { status: "ready" }, status: :ok
rescue => e
  render json: { status: "error", message: e.message }, status: :service_unavailable
end
```

### Backup Strategies

#### Database Backup Configuration

```yaml
# config/deploy.yml
accessories:
  backup:
    image: postgres:17.5-alpine
    host: backup.your-domain.com
    cmd: >
      sh -c "
        while true; do
          pg_dump -h ${DB_HOST} -U ${DB_USER} -d ${DB_NAME} | 
          gzip > /backups/listopia_$(date +%Y%m%d_%H%M%S).sql.gz &&
          find /backups -name '*.sql.gz' -mtime +7 -delete
          sleep 86400
        done
      "
    env:
      clear:
        DB_HOST: your-db-host.com
        DB_NAME: listopia_production
        DB_USER: listopia
      secret:
        - PGPASSWORD
    volumes:
      - backup_data:/backups
```

#### Automated S3 Backup

```bash
# Create backup script: bin/backup
#!/bin/bash
set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="listopia_backup_${TIMESTAMP}.sql.gz"

# Create database backup
pg_dump $DATABASE_URL | gzip > "/tmp/$BACKUP_FILE"

# Upload to S3
aws s3 cp "/tmp/$BACKUP_FILE" "s3://your-backup-bucket/database/"

# Clean up local file
rm "/tmp/$BACKUP_FILE"

# Remove old backups (keep 30 days)
aws s3 ls "s3://your-backup-bucket/database/" | 
  while read -r line; do
    createDate=$(echo $line | awk '{print $1" "$2}')
    createDate=$(date -d "$createDate" +%s)
    olderThan=$(date -d "30 days ago" +%s)
    if [[ $createDate -lt $olderThan ]]; then
      fileName=$(echo $line | awk '{print $4}')
      aws s3 rm "s3://your-backup-bucket/database/$fileName"
    fi
  done
```

#### Backup Cron Job

```yaml
# config/deploy.yml
accessories:
  backup:
    image: amazon/aws-cli:latest
    host: backup.your-domain.com
    cmd: >
      sh -c "
        echo '0 2 * * * /app/bin/backup' | crontab - &&
        crond -f
      "
    env:
      secret:
        - AWS_ACCESS_KEY_ID
        - AWS_SECRET_ACCESS_KEY
        - DATABASE_URL
    volumes:
      - "./bin/backup:/app/bin/backup:ro"
```

### Zero-Downtime Deployment Strategies

#### Rolling Deployments

```yaml
# config/deploy.yml
builder:
  multiarch: false  # Faster builds
  cache:
    type: gha  # GitHub Actions cache

# Rolling deployment configuration
boot:
  limit: 1  # Deploy one server at a time
  wait: 30  # Wait 30 seconds between deployments

proxy:
  buffering:
    requests: 1000
    memory: 1mb
  response_timeout: 60
```

#### Blue-Green Deployment

```bash
# Deploy to staging slot
bundle exec kamal deploy --destination staging

# Test staging deployment
curl https://staging.your-domain.com/health

# Switch traffic to staging (makes it production)
bundle exec kamal proxy deploy --destination staging

# Rollback if needed
bundle exec kamal rollback
```

### Performance Optimization

#### Asset and CDN Configuration

```yaml
# config/deploy.yml
env:
  clear:
    # CDN configuration
    ASSET_HOST: https://cdn.your-domain.com
    CDN_URL: https://cdn.your-domain.com
    
    # Asset optimization
    RAILS_SERVE_STATIC_FILES: false  # Let nginx/proxy handle assets
```

#### Resource Limits

```yaml
# config/deploy.yml
servers:
  web:
    - web1.your-domain.com
    - web2.your-domain.com
    options:
      memory: 2g
      cpus: 2
      memory-swap: 4g

env:
  clear:
    # Puma configuration
    WEB_CONCURRENCY: 3
    RAILS_MAX_THREADS: 5
    
    # Database pool
    DB_POOL_SIZE: 15
```

### Kamal Commands Reference

```bash
# Initial setup
bundle exec kamal setup

# Deploy
bundle exec kamal deploy

# Deploy specific role
bundle exec kamal deploy --roles web

# Check app status
bundle exec kamal app details
bundle exec kamal app logs
bundle exec kamal app logs --follow

# Proxy management
bundle exec kamal proxy status
bundle exec kamal proxy logs

# Rollback
bundle exec kamal rollback

# Scale services
bundle exec kamal app scale web=3

# Execute commands
bundle exec kamal app exec "bin/rails console"
bundle exec kamal app exec --interactive "bash"

# Accessory management
bundle exec kamal accessory details redis
bundle exec kamal accessory logs redis

# Environment management
bundle exec kamal env push  # Push .kamal/secrets to servers
bundle exec kamal env show  # Show current environment
```

## Troubleshooting

### Common Issues:

1. **Email not working:**
   - Check SMTP credentials
   - Verify firewall settings
   - Test SMTP connection manually

2. **Database connection issues:**
   - Verify database credentials
   - Check network connectivity
   - Ensure PostgreSQL extensions are installed

3. **Asset compilation fails:**
   - Ensure Node.js/Bun is available in Docker
   - Check asset pipeline configuration
   - Verify file permissions

4. **SSL certificate issues:**
   - Ensure domain points to server
   - Check ports 80/443 are accessible
   - Verify no other services conflict

### Getting Help:

- Check Kamal documentation: https://kamal-deploy.org
- Rails deployment guide: https://guides.rubyonrails.org/deployment.html
- Open an issue in the Listopia repository

## Security Checklist

- [ ] Use strong database passwords
- [ ] Rotate Rails master key regularly
- [ ] Enable SSL/TLS for all connections
- [ ] Configure firewall properly
- [ ] Regular security updates
- [ ] Monitor application logs
- [ ] Backup database regularly
- [ ] Use environment variables for secrets