#!/usr/bin/env node

const QueueManager = require('./queue-manager');
const path = require('path');
require('dotenv').config();

class PDFWorker {
    constructor() {
        this.queueManager = new QueueManager();
        this.isRunning = false;
        this.workerId = `worker-${process.pid}-${Date.now()}`;
        
        console.log(`🚀 PDF Worker started: ${this.workerId}`);
        this.setupGracefulShutdown();
    }

    async start() {
        this.isRunning = true;
        console.log('🔄 Worker is running and processing jobs...');
        
        // Keep the worker alive
        while (this.isRunning) {
            await this.sleep(1000);
        }
    }

    async stop() {
        console.log('🛑 Stopping worker...');
        this.isRunning = false;
        
        // Wait for current jobs to complete
        await this.sleep(5000);
        process.exit(0);
    }

    setupGracefulShutdown() {
        process.on('SIGTERM', async () => {
            console.log('📡 Received SIGTERM, shutting down gracefully...');
            await this.stop();
        });

        process.on('SIGINT', async () => {
            console.log('📡 Received SIGINT, shutting down gracefully...');
            await this.stop();
        });

        process.on('uncaughtException', (error) => {
            console.error('💥 Uncaught Exception:', error);
            this.stop();
        });

        process.on('unhandledRejection', (reason, promise) => {
            console.error('💥 Unhandled Rejection at:', promise, 'reason:', reason);
        });
    }

    sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    async getStats() {
        return await this.queueManager.getAllStats();
    }
}

// Start worker if this file is run directly
if (require.main === module) {
    const worker = new PDFWorker();
    worker.start().catch(console.error);
}

module.exports = PDFWorker;
