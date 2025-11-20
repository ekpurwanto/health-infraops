// Health-InfraOps Infokes Application Server

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const morgan = require('morgan');
const rateLimit = require('rate-limiter-flexible');
const winston = require('winston');
require('dotenv').config();

// Initialize Express app
const app = express();
const PORT = process.env.PORT || 3000;

// Configure logger
const logger = winston.createLogger({
    level: 'info',
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
    ),
    transports: [
        new winston.transports.File({ filename: '/var/log/infokes/error.log', level: 'error' }),
        new winston.transports.File({ filename: '/var/log/infokes/combined.log' }),
        new winston.transports.Console({
            format: winston.format.simple()
        })
    ]
});

// Rate limiting
const rateLimiter = new rateLimit.RateLimiterMemory({
    keyGenerator: (req) => req.ip,
    points: 10, // Number of requests
    duration: 1, // Per second
    blockDuration: 300, // Block for 5 minutes if exceeded
});

// Rate limiting middleware
const rateLimitMiddleware = async (req, res, next) => {
    try {
        await rateLimiter.consume(req.ip);
        next();
    } catch (rejRes) {
        logger.warn(`Rate limit exceeded for IP: ${req.ip}`);
        res.status(429).json({
            error: 'Too Many Requests',
            message: 'Rate limit exceeded. Please try again later.'
        });
    }
};

// Security middleware
app.use(helmet({
    contentSecurityPolicy: {
        directives: {
            defaultSrc: ["'self'"],
            scriptSrc: ["'self'", "'unsafe-inline'"],
            styleSrc: ["'self'", "'unsafe-inline'"],
            imgSrc: ["'self'", "data:", "https:"],
        },
    },
    crossOriginEmbedderPolicy: false
}));

// CORS configuration
app.use(cors({
    origin: [
        'https://infokes.co.id',
        'https://www.infokes.co.id',
        'https://app.infokes.co.id'
    ],
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With']
}));

// Compression
app.use(compression());

// Logging middleware
app.use(morgan('combined', {
    stream: { write: (message) => logger.info(message.trim()) }
}));

// Body parsing middleware
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Apply rate limiting to all routes
app.use(rateLimitMiddleware);

// Health check endpoint
app.get('/health', (req, res) => {
    const healthcheck = {
        uptime: process.uptime(),
        message: 'OK',
        timestamp: new Date().toISOString(),
        service: 'Infokes API',
        version: '1.0.0'
    };
    
    logger.info('Health check performed', { ip: req.ip });
    res.status(200).json(healthcheck);
});

// API Routes
app.use('/api/v1/patients', require('./routes/patients'));
app.use('/api/v1/appointments', require('./routes/appointments'));
app.use('/api/v1/medical-records', require('./routes/medical-records'));
app.use('/api/v1/users', require('./routes/users'));

// Root endpoint
app.get('/', (req, res) => {
    res.json({
        message: 'Health-InfraOps Infokes API',
        version: '1.0.0',
        documentation: 'https://docs.infokes.co.id',
        status: 'operational'
    });
});

// 404 handler
app.use('*', (req, res) => {
    logger.warn(`404 Not Found: ${req.originalUrl}`, { ip: req.ip });
    res.status(404).json({
        error: 'Not Found',
        message: 'The requested resource was not found.'
    });
});

// Global error handler
app.use((err, req, res, next) => {
    logger.error('Unhandled error', {
        error: err.message,
        stack: err.stack,
        ip: req.ip,
        url: req.originalUrl
    });

    // Don't leak error details in production
    const errorResponse = {
        error: 'Internal Server Error',
        message: process.env.NODE_ENV === 'development' ? err.message : 'Something went wrong!'
    };

    res.status(err.status || 500).json(errorResponse);
});

// Graceful shutdown
process.on('SIGTERM', () => {
    logger.info('SIGTERM received, starting graceful shutdown');
    server.close(() => {
        logger.info('Process terminated');
        process.exit(0);
    });
});

process.on('SIGINT', () => {
    logger.info('SIGINT received, starting graceful shutdown');
    server.close(() => {
        logger.info('Process terminated');
        process.exit(0);
    });
});

// Start server
const server = app.listen(PORT, '0.0.0.0', () => {
    logger.info(`Infokes API server running on port ${PORT}`, {
        port: PORT,
        environment: process.env.NODE_ENV || 'development',
        node_version: process.version
    });
    
    console.log(`🚀 Infokes API Server running on port ${PORT}`);
    console.log(`📊 Environment: ${process.env.NODE_ENV || 'development'}`);
    console.log(`🩺 Service: Health Infrastructure Operations`);
});

module.exports = app;