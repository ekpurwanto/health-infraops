// Health-InfraOps PM2 Ecosystem Configuration

module.exports = {
    apps: [{
        name: 'infokes-api',
        script: './server.js',
        instances: 'max',
        exec_mode: 'cluster',
        watch: false,
        env: {
            NODE_ENV: 'development',
            PORT: 3000,
            LOG_LEVEL: 'debug'
        },
        env_production: {
            NODE_ENV: 'production',
            PORT: 3000,
            LOG_LEVEL: 'info'
        },
        // Logging configuration
        log_file: '/var/log/infokes/combined.log',
        error_file: '/var/log/infokes/error.log',
        out_file: '/var/log/infokes/out.log',
        merge_logs: true,
        log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
        
        // Process management
        max_memory_restart: '1G',
        min_uptime: '10s',
        max_restarts: 10,
        restart_delay: 4000,
        kill_timeout: 5000,
        
        // Health monitoring
        listen_timeout: 3000,
        kill_timeout: 5000,
        
        // Advanced features
        source_map_support: true,
        instance_var: 'INSTANCE_ID',
        
        // Environment specific
        env_development: {
            NODE_ENV: 'development',
            WATCH: true
        },
        env_staging: {
            NODE_ENV: 'staging',
            PORT: 3000
        },
        env_production: {
            NODE_ENV: 'production',
            PORT: 3000,
            instances: 4
        }
    }, {
        name: 'infokes-worker',
        script: './workers/main.js',
        instances: 2,
        exec_mode: 'cluster',
        env: {
            NODE_ENV: 'production',
            WORKER_TYPE: 'general'
        },
        // Worker specific settings
        max_memory_restart: '512M',
        kill_timeout: 2000,
        restart_delay: 1000
    }],
    
    // Deployment configuration
    deploy: {
        production: {
            user: 'health-infraops',
            host: ['10.0.10.11', '10.0.10.12'],
            ref: 'origin/main',
            repo: 'https://github.com/ekpurwanto/health-infraops.git',
            path: '/opt/infokes/production',
            'post-deploy': 'npm install && pm2 reload ecosystem.config.js --env production',
            env: {
                NODE_ENV: 'production'
            }
        },
        staging: {
            user: 'health-infraops',
            host: ['10.0.10.13'],
            ref: 'origin/develop',
            repo: 'https://github.com/ekpurwanto/health-infraops.git',
            path: '/opt/infokes/staging',
            'post-deploy': 'npm install && pm2 reload ecosystem.config.js --env staging',
            env: {
                NODE_ENV: 'staging'
            }
        }
    }
};